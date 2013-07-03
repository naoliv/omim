#import "MapViewController.h"
#import "SearchVC.h"
#import "MapsAppDelegate.h"
#import "EAGLView.h"
#import "BookmarksRootVC.h"
#import "PlacePageVC.h"
#import "GetActiveConnectionType.h"
#import "PlacePreviewViewController.h"

#import "../Settings/SettingsManager.h"

#import "../../Common/CustomAlertView.h"

#include "Framework.h"
#include "RenderContext.hpp"

#include "../../../anim/controller.hpp"

#include "../../../gui/controller.hpp"

#include "../../../platform/platform.hpp"

#include "../Statistics/Statistics.h"

#include "../../../map/dialog_settings.hpp"


#define FACEBOOK_ALERT_VIEW 1
#define APPSTORE_ALERT_VIEW 2
#define ITUNES_URL @"itms-apps://ax.itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?type=Purple+Software&id=%lld"
#define FACEBOOK_URL @"http://www.facebook.com/MapsWithMe"
#define FACEBOOK_SCHEME @"fb://profile/111923085594432"

const long long PRO_IDL = 510623322L;
const long long LITE_IDL = 431183278L;


@implementation MapViewController

@synthesize m_myPositionButton;


- (void) Invalidate
{
  Framework & f = GetFramework();
  if (!f.SetUpdatesEnabled(true))
    f.Invalidate();
}

//********************************************************************************************
//*********************** Callbacks from LocationManager *************************************
- (void) onLocationError:(location::TLocationError)errorCode
{
  GetFramework().OnLocationError(errorCode);

  switch (errorCode)
  {
    case location::EDenied:
    {
      UIAlertView * alert = [[CustomAlertView alloc] initWithTitle:nil
                                                       message:NSLocalizedString(@"location_is_disabled_long_text", @"Location services are disabled by user alert - message")
                                                      delegate:nil 
                                             cancelButtonTitle:NSLocalizedString(@"ok", @"Location Services are disabled by user alert - close alert button")
                                             otherButtonTitles:nil];
      [alert show];
      [alert release];
      [[MapsAppDelegate theApp].m_locationManager stop:self];
    }
    break;

    case location::ENotSupported:
    {
      UIAlertView * alert = [[CustomAlertView alloc] initWithTitle:nil
                                                       message:NSLocalizedString(@"device_doesnot_support_location_services", @"Location Services are not available on the device alert - message")
                                                      delegate:nil
                                             cancelButtonTitle:NSLocalizedString(@"ok", @"Location Services are not available on the device alert - close alert button")
                                             otherButtonTitles:nil];
      [alert show];
      [alert release];
      [[MapsAppDelegate theApp].m_locationManager stop:self];
    }
    break;

  default:
    break;
  }
}

- (void) onLocationUpdate:(location::GpsInfo const &)info
{
  Framework & f = GetFramework();

  if (f.GetLocationState()->IsFirstPosition())
  {
    [m_myPositionButton setImage:[UIImage imageNamed:@"location-selected.png"] forState:UIControlStateSelected];
  }

  f.OnLocationUpdate(info);

  [self showPopover];
}

- (void) onCompassUpdate:(location::CompassInfo const &)info
{
  GetFramework().OnCompassUpdate(info);
}

- (void) onCompassStatusChanged:(int) newStatus
{
  Framework & f = GetFramework();
  shared_ptr<location::State> ls = f.GetLocationState();
  
  if (newStatus == location::ECompassFollow)
    [m_myPositionButton setImage:[UIImage imageNamed:@"location-follow.png"] forState:UIControlStateSelected];
  else
  {
    if (ls->HasPosition())
      [m_myPositionButton setImage:[UIImage imageNamed:@"location-selected.png"] forState:UIControlStateSelected];
    else
      [m_myPositionButton setImage:[UIImage imageNamed:@"location.png"] forState:UIControlStateSelected];
    
    m_myPositionButton.selected = YES;
  }
}

//********************************************************************************************
//********************************************************************************************

- (IBAction)OnMyPositionClicked:(id)sender
{
  Framework & f = GetFramework();
  shared_ptr<location::State> ls = f.GetLocationState();

  if (!ls->HasPosition())
  {
    if (!ls->IsFirstPosition())
    {
      m_myPositionButton.selected = YES;
      [m_myPositionButton setImage:[UIImage imageNamed:@"location-search.png"] forState:UIControlStateSelected];

      ls->OnStartLocation();

      [[MapsAppDelegate theApp] disableStandby];
      [[MapsAppDelegate theApp].m_locationManager start:self];

      return;
    }
  }
  else
  {
    if (!ls->IsCentered())
    {
      ls->AnimateToPositionAndEnqueueLocationProcessMode(location::ELocationCenterOnly);
      m_myPositionButton.selected = YES;
      return;
    }
    else
      if (GetPlatform().IsPro())
      {
        if (ls->HasCompass())
        {
          if (ls->GetCompassProcessMode() != location::ECompassFollow)
          {
            if (ls->IsCentered())
              ls->StartCompassFollowing();
            else
              ls->AnimateToPositionAndEnqueueFollowing();

            m_myPositionButton.selected = YES;
            [m_myPositionButton setImage:[UIImage imageNamed:@"location-follow.png"] forState:UIControlStateSelected];

            return;
          }
          else
          {
            anim::Controller *animController = f.GetAnimController();
            animController->Lock();

            f.GetInformationDisplay().locationState()->StopCompassFollowing();
        
            double startAngle = f.GetNavigator().Screen().GetAngle();
            double endAngle = 0;
       
            f.GetAnimator().RotateScreen(startAngle, endAngle);
        
            animController->Unlock();
        
            f.Invalidate();
          }
      }
    }
  }

  ls->OnStopLocation();

  [[MapsAppDelegate theApp] enableStandby];
  [[MapsAppDelegate theApp].m_locationManager stop:self];

  m_myPositionButton.selected = NO;
  [m_myPositionButton setImage:[UIImage imageNamed:@"location.png"] forState:UIControlStateSelected];
}

- (IBAction)OnSettingsClicked:(id)sender
{
  [[[MapsAppDelegate theApp] settingsManager] show:self];
}

- (IBAction)OnSearchClicked:(id)sender
{
  SearchVC * searchVC = [[SearchVC alloc] init];
  [self presentModalViewController:searchVC animated:YES];
  [searchVC release];
}

- (IBAction)OnBookmarksClicked:(id)sender
{
  BookmarksRootVC * bVC = [[BookmarksRootVC alloc] init];
  UINavigationController * navC = [[UINavigationController alloc] initWithRootViewController:bVC];
  [self presentModalViewController:navC animated:YES];
  [bVC release];
  [navC release];
}

- (void)popoverControllerDidDismissPopover:(UIPopoverController *)popoverController
{
  [self destroyPopover];
  [self Invalidate];
}

- (void) processMapClickAtPoint:(CGPoint)point longClick:(BOOL)isLongClick
{
  CGFloat const scaleFactor = self.view.contentScaleFactor;
  m2::PointD pxClicked(point.x * scaleFactor, point.y * scaleFactor);
  GetFramework().GetBalloonManager().OnClick(m2::PointD(pxClicked.x, pxClicked.y), isLongClick);
}

- (void) onSingleTap:(NSValue *)point
{
  [self processMapClickAtPoint:[point CGPointValue] longClick:NO];
}

- (void) onLongTap:(NSValue *)point
{
  [self processMapClickAtPoint:[point CGPointValue] longClick:YES];
}

- (void)showSearchResultAsBookmarkAtMercatorPoint:(const m2::PointD &)pt withInfo:(const search::AddressInfo &)info
{
  GetFramework().GetBalloonManager().ShowAddress(pt, info);
}

- (void)showBalloonWithCategoryIndex:(int)cat andBookmarkIndex:(int)bm
{
  GetFramework().GetBalloonManager().ShowBookmark(BookmarkAndCategory(cat,bm));
}

- (id) initWithCoder: (NSCoder *)coder
{
  NSLog(@"MapViewController initWithCoder Started");

  if ((self = [super initWithCoder:coder]))
  {
    self.title = NSLocalizedString(@"back", @"Back button in nav bar to show the map");

    Framework & f = GetFramework();

    typedef void (*POSITIONBalloonFnT)(id,SEL, double, double);
    typedef void (*POIBalloonFnT)(id, SEL, m2::PointD const &, search::AddressInfo const &);
    typedef void (*APIPOINTBalloonFnT)(id,SEL, url_scheme::ApiPoint const &);
    typedef void (*BOOKMARKBalloonFnT)(id,SEL, BookmarkAndCategory const &);

    BalloonManager & manager = f.GetBalloonManager();

    SEL positionSel = @selector(positionBallonClickedLat:lon:);
    POSITIONBalloonFnT positionFn = (POSITIONBalloonFnT)[self methodForSelector:positionSel];
    manager.ConnectPositionListener(bind(positionFn, self, positionSel,_1,_2));

    SEL ballonPOIsel = @selector(poiBalloonClicked:info:);
    POIBalloonFnT balloonFn = (POIBalloonFnT)[self methodForSelector:ballonPOIsel];
    manager.ConnectPoiListener(bind(balloonFn, self, ballonPOIsel, _1, _2));

    SEL apiPointSel = @selector(apiBalloonClicked:);
    APIPOINTBalloonFnT apiFn = (APIPOINTBalloonFnT)[self methodForSelector:apiPointSel];
    manager.ConnectApiListener(bind(apiFn, self, apiPointSel, _1));

    SEL bookmarkSel = @selector(bookmarkBalloonClicked:);
    BOOKMARKBalloonFnT bookmarkFn = (BOOKMARKBalloonFnT)[self methodForSelector:bookmarkSel];
    manager.ConnectBookmarkListener(bind(bookmarkFn, self, bookmarkSel, _1));

    typedef void (*CompassStatusFnT)(id, SEL, int);
    SEL compassStatusSelector = @selector(onCompassStatusChanged:);
    CompassStatusFnT compassStatusFn = (CompassStatusFnT)[self methodForSelector:compassStatusSelector];

    shared_ptr<location::State> ls = f.GetLocationState();
    ls->AddCompassStatusListener(bind(compassStatusFn, self, compassStatusSelector, _1));

    m_StickyThreshold = 10;

    m_CurrentAction = NOTHING;

    EAGLView * v = (EAGLView *)self.view;
    [v initRenderPolicy];

    // restore previous screen position
    if (!f.LoadState())
      f.SetMaxWorldRect();
    
    _isApiMode = NO;

    f.Invalidate();
    f.LoadBookmarks();
  }

  NSLog(@"MapViewController initWithCoder Ended");
  return self;
}

NSInteger compareAddress(id l, id r, void * context)
{
	return l < r;
}

- (void) updatePointsFromEvent:(UIEvent*)event
{
	NSSet * allTouches = [event allTouches];

  UIView * v = self.view;
  CGFloat const scaleFactor = v.contentScaleFactor;

  // 0 touches are possible from touchesCancelled.
  switch ([allTouches count])
  {
    case 0:
      break;

    case 1:
    {
      CGPoint const pt = [[[allTouches allObjects] objectAtIndex:0] locationInView:v];
      m_Pt1 = m2::PointD(pt.x * scaleFactor, pt.y * scaleFactor);
      break;
    }

    default:
    {
      NSArray * sortedTouches = [[allTouches allObjects] sortedArrayUsingFunction:compareAddress context:NULL];
      CGPoint const pt1 = [[sortedTouches objectAtIndex:0] locationInView:v];
      CGPoint const pt2 = [[sortedTouches objectAtIndex:1] locationInView:v];

      m_Pt1 = m2::PointD(pt1.x * scaleFactor, pt1.y * scaleFactor);
      m_Pt2 = m2::PointD(pt2.x * scaleFactor, pt2.y * scaleFactor);
      break;
    }
  }
}

- (void) stopCurrentAction
{
	switch (m_CurrentAction)
	{
		case NOTHING:
			break;
		case DRAGGING:
			GetFramework().StopDrag(DragEvent(m_Pt1.x, m_Pt1.y));
			break;
		case SCALING:
			GetFramework().StopScale(ScaleEvent(m_Pt1.x, m_Pt1.y, m_Pt2.x, m_Pt2.y));
			break;
	}

	m_CurrentAction = NOTHING;
}

- (void) touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
  // To cancel single tap timer
  UITouch * theTouch = (UITouch *)[touches anyObject];
  if (theTouch.tapCount > 1)
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

	[self updatePointsFromEvent:event];

  Framework & f = GetFramework();

	if ([[event allTouches] count] == 1)
	{
    if (f.GetGuiController()->OnTapStarted(m_Pt1))
      return;
    
		f.StartDrag(DragEvent(m_Pt1.x, m_Pt1.y));
		m_CurrentAction = DRAGGING;

    // Start long-tap timer
    [self performSelector:@selector(onLongTap:) withObject:[NSValue valueWithCGPoint:[theTouch locationInView:self.view]] afterDelay:1.0];
    // Temporary solution to filter long touch
    m_touchDownPoint = m_Pt1;
	}
	else
	{
		f.StartScale(ScaleEvent(m_Pt1.x, m_Pt1.y, m_Pt2.x, m_Pt2.y));
		m_CurrentAction = SCALING;
	}

	m_isSticking = true;
}

- (void) touchesMoved:(NSSet*)touches withEvent:(UIEvent*)event
{
  m2::PointD const TempPt1 = m_Pt1;
	m2::PointD const TempPt2 = m_Pt2;

	[self updatePointsFromEvent:event];

  // Cancel long-touch timer
  if (!m_touchDownPoint.EqualDxDy(m_Pt1, 9))
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

  Framework & f = GetFramework();

  if (f.GetGuiController()->OnTapMoved(m_Pt1))
    return;
  
	if (m_isSticking)
	{
		if ((TempPt1.Length(m_Pt1) > m_StickyThreshold) || (TempPt2.Length(m_Pt2) > m_StickyThreshold))
    {
			m_isSticking = false;
    }
		else
		{
			// Still stickying. Restoring old points and return.
			m_Pt1 = TempPt1;
			m_Pt2 = TempPt2;
			return;
		}
	}

	switch (m_CurrentAction)
	{
	case DRAGGING:
		f.DoDrag(DragEvent(m_Pt1.x, m_Pt1.y));
//		needRedraw = true;
		break;
	case SCALING:
		if ([[event allTouches] count] < 2)
			[self stopCurrentAction];
		else
		{
			f.DoScale(ScaleEvent(m_Pt1.x, m_Pt1.y, m_Pt2.x, m_Pt2.y));
//			needRedraw = true;
		}
		break;
	case NOTHING:
		return;
	}
}

- (void) touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
	[self updatePointsFromEvent:event];
	[self stopCurrentAction];

  UITouch * theTouch = (UITouch*)[touches anyObject];
  int tapCount = theTouch.tapCount;
  int touchesCount = [[event allTouches] count];

  Framework & f = GetFramework();

  if (touchesCount == 1)
  {
    // Cancel long-touch timer
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    
    // TapCount could be zero if it was a single long (or moving) tap.
    if (tapCount < 2)
    {
      if (f.GetGuiController()->OnTapEnded(m_Pt1))
        return;
    }

    if (tapCount == 1)
    {
      // Launch single tap timer
      if (m_isSticking)
        [self performSelector:@selector(onSingleTap:) withObject:[NSValue valueWithCGPoint:[theTouch locationInView:self.view]] afterDelay:0.3];
    }
    else if (tapCount == 2 && m_isSticking)
      f.ScaleToPoint(ScaleToPointEvent(m_Pt1.x, m_Pt1.y, 2.0));
  }

  if (touchesCount == 2 && tapCount == 1 && m_isSticking)
  {
    f.Scale(0.5);
    if (!m_touchDownPoint.EqualDxDy(m_Pt1, 9))
      [NSObject cancelPreviousPerformRequestsWithTarget:self];
    m_isSticking = NO;
  }
}

- (void) touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event
{
  [NSObject cancelPreviousPerformRequestsWithTarget:self];

  [self updatePointsFromEvent:event];
  [self stopCurrentAction];
}

- (BOOL) shouldAutorotateToInterfaceOrientation: (UIInterfaceOrientation) interfaceOrientation
{
	return YES; // We support all orientations
}

- (void) didReceiveMemoryWarning
{
	GetFramework().MemoryWarning();
  [super didReceiveMemoryWarning];
}

- (void) viewDidUnload
{
  // to correctly release view on memory warnings
  self.m_myPositionButton = nil;
  [super viewDidUnload];
}

- (void) OnTerminate
{
  GetFramework().SaveState();
}

- (void) didRotateFromInterfaceOrientation: (UIInterfaceOrientation) fromInterfaceOrientation
{
  [[MapsAppDelegate theApp].m_locationManager setOrientation:self.interfaceOrientation];
  [self showPopover];
  [self Invalidate];
}

- (void) OnEnterBackground
{
  [[Statistics instance] stopSession];
  
  // Save state and notify about entering background.

  Framework & f = GetFramework();
  f.SaveState();
  f.SetUpdatesEnabled(false);
  f.EnterBackground();
}

- (void) OnEnterForeground
{
  // Notify about entering foreground (should be called on the first launch too).
  GetFramework().EnterForeground();

  if (self.isViewLoaded && self.view.window)
    [self Invalidate]; // only invalidate when map is displayed on the screen

  if (GetActiveConnectionType() != ENotConnected)
  {
    if (dlg_settings::ShouldShow(dlg_settings::AppStore))
      [self showAppStoreRatingMenu];
    else if (dlg_settings::ShouldShow(dlg_settings::FacebookDlg))
      [self showFacebookRatingMenu];
  }
}

- (void) viewWillAppear:(BOOL)animated
{
  [self Invalidate];
  [super viewWillAppear:animated];
}

- (void) viewWillDisappear:(BOOL)animated
{
  GetFramework().SetUpdatesEnabled(false);
  [super viewWillDisappear:animated];
}

- (void) SetupMeasurementSystem
{
  GetFramework().SetupMeasurementSystem();
}

- (void)showAppStoreRatingMenu
{
  UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:@"App Store"
                                                      message:NSLocalizedString(@"appStore_message", nil)
                                                      delegate:self
                                            cancelButtonTitle:NSLocalizedString(@"no_thanks", nil)
                                            otherButtonTitles:NSLocalizedString(@"ok", nil), NSLocalizedString(@"remind_me_later", nil), nil];
  alertView.tag = APPSTORE_ALERT_VIEW;
  [alertView show];
  [alertView release];
}

-(void)showFacebookRatingMenu
{
  UIAlertView * alertView = [[UIAlertView alloc] initWithTitle:@"Facebook"
                                                      message:NSLocalizedString(@"share_on_facebook_text", nil)
                                                     delegate:self
                                            cancelButtonTitle:NSLocalizedString(@"no_thanks", nil)
                                            otherButtonTitles:NSLocalizedString(@"ok", nil), NSLocalizedString(@"remind_me_later", nil),  nil];
  alertView.tag = FACEBOOK_ALERT_VIEW;
  [alertView show];
  [alertView release];
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
  switch (alertView.tag)
  {
    case APPSTORE_ALERT_VIEW:
    {
      NSString * url = nil;
      if (GetPlatform().IsPro())
        url = [NSString stringWithFormat: ITUNES_URL, PRO_IDL];
      else
        url = [NSString stringWithFormat: ITUNES_URL, LITE_IDL];
      [self manageAlert:buttonIndex andUrl:[NSURL URLWithString: url] andDlgSetting:dlg_settings::AppStore];
      return;
    }
    case FACEBOOK_ALERT_VIEW:
    {
      NSString * url = [NSString stringWithFormat: FACEBOOK_SCHEME];
      if (![[UIApplication sharedApplication] canOpenURL: [NSURL URLWithString: url]])
        url = [NSString stringWithFormat: FACEBOOK_URL];
      [self manageAlert:buttonIndex andUrl:[NSURL URLWithString: url] andDlgSetting:dlg_settings::FacebookDlg];
      return;
    }
    default:
      break;
  }
}

-(void) manageAlert:(NSInteger)buttonIndex andUrl:(NSURL*)url andDlgSetting:(dlg_settings::DialogT)set
{
  switch (buttonIndex)
  {
    case 0:
    {
      dlg_settings::SaveResult(set, dlg_settings::Never);
      break;
    }
    case 1:
    {
      dlg_settings::SaveResult(set, dlg_settings::OK);
      [[UIApplication sharedApplication] openURL: url];
      break;
    }
    case 2:
    {
      dlg_settings::SaveResult(set, dlg_settings::Later);
      break;
    }
    default:
      break;
  }
}

- (void) destroyPopover
{
  [m_popover release];
  m_popover = nil;
}

-(void)showPopover
{
  if (m_popover)
    GetFramework().GetBalloonManager().Hide();

  double const sf = self.view.contentScaleFactor;

  Framework & f = GetFramework();
  m2::PointD tmp = m2::PointD(f.GtoP(m2::PointD(m_popoverPos.x, m_popoverPos.y)));

  [m_popover presentPopoverFromRect:CGRectMake(tmp.x / sf, tmp.y / sf, 1, 1) inView:self.view permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
}

- (void)prepareForApi
{
  _isApiMode = YES;
  if ([self shouldShowNavBar])
  {
    self.navigationController.navigationBarHidden = NO;
    UIBarButtonItem * closeButton = [[[UIBarButtonItem alloc] initWithTitle:NSLocalizedString(@"back", nil) style: UIBarButtonItemStyleDone target:self action:@selector(returnToApiApp)] autorelease];
    self.navigationItem.leftBarButtonItem = closeButton;
    self.navigationItem.title = [NSString stringWithUTF8String:GetFramework().GetMapApiAppTitle().c_str()];
  }
}

- (void) clearApiMode
{
  _isApiMode = NO;
  self.navigationController.navigationItem.title = @"";
  GetFramework().ClearMapApiPoints();
  [self Invalidate];
  [self.navigationController setNavigationBarHidden:YES animated:YES];
  GetFramework().GetBalloonManager().Hide();
}

-(void)returnToApiApp
{
  NSString * backUrl = [NSString stringWithUTF8String:GetFramework().GetMapApiBackUrl().c_str()];
  [[UIApplication sharedApplication] openURL:[NSURL URLWithString:backUrl]];
  [self clearApiMode];
}

-(BOOL) shouldShowNavBar
{
  Framework & f = GetFramework();
  NSString * backUrl = [NSString stringWithUTF8String:f.GetMapApiBackUrl().c_str()];
  return (_isApiMode && [backUrl length] && [[UIApplication sharedApplication] canOpenURL:[NSURL URLWithString:backUrl]]);
}

- (void)dismissPopover
{
  [m_popover dismissPopoverAnimated:YES];
  [self destroyPopover];
  [self Invalidate];
}

-(void)positionBallonClickedLat:(double)lat lon:(double)lon
{
  CGPoint const p = CGPointMake(MercatorBounds::LonToX(lon), MercatorBounds::LatToY(lat));
  PlacePreviewViewController * preview = [[PlacePreviewViewController alloc] initWithPoint:p];
  m_popoverPos = p;
  [self pushViewController:preview];
  [preview release];
}

-(void)poiBalloonClicked:(m2::PointD const &)pt info:(search::AddressInfo const &)info
{
  PlacePreviewViewController * preview = [[PlacePreviewViewController alloc] initWith:info point:CGPointMake(pt.x, pt.y)];
  m_popoverPos = CGPointMake(pt.x, pt.y);
  [self pushViewController:preview];
  [preview release];
}

-(void)apiBalloonClicked:(url_scheme::ApiPoint const &) apiPoint
{
  PlacePreviewViewController * apiPreview = [[PlacePreviewViewController alloc] initWithApiPoint:apiPoint];
  m_popoverPos = CGPointMake(MercatorBounds::LonToX(apiPoint.m_lon), MercatorBounds::LatToY(apiPoint.m_lat));
  [self pushViewController:apiPreview];
  [apiPreview release];
}

-(void)bookmarkBalloonClicked:(BookmarkAndCategory const &) bmAndCat
{
  PlacePageVC * vc = [[PlacePageVC alloc] initWithBookmark:bmAndCat];
  Bookmark const * bm = GetFramework().GetBmCategory(bmAndCat.first)->GetBookmark(bmAndCat.second);
  m_popoverPos = CGPointMake(bm->GetOrg().x, bm->GetOrg().y);
  [self pushViewController:vc];
  [vc release];
}

-(void)pushViewController:(UIViewController *)vc
{
  if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
  {
    UINavigationController * navC = [[UINavigationController alloc] init];
    m_popover = [[UIPopoverController alloc] initWithContentViewController:navC];
    m_popover.delegate = self;

    [navC pushViewController:vc animated:YES];
    [navC release];
    navC.navigationBar.barStyle = UIBarStyleBlack;

    [m_popover setPopoverContentSize:CGSizeMake(320, 480)];
    [self showPopover];
  }
  else
    [self.navigationController pushViewController:vc animated:YES];
}

@end
