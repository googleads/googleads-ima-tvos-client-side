/**
 * Copyright 2019 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *  https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
#import "ViewController.h"

#import <AVKit/AVKit.h>

#import <GoogleInteractiveMediaAds/GoogleInteractiveMediaAds.h>

NSString *const kContentURLString =
    @"https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/"
    @"master.m3u8";
NSString *const kAdTagURLString = @"https://pubads.g.doubleclick.net/gampad/ads?sz=640x480&"
    @"iu=/124319096/external/ad_rule_samples&ciu_szs=300x250&ad_rule=1&impl=s&gdfp_req=1&env=vp&"
    @"output=vmap&unviewed_position_start=1&cust_params=deployment%3Ddevsite%26sample_ar%3D"
    @"premidpostlongpod&cmsid=496&vid=short_tencue&correlator=[TIMESTAMP]";

@interface ViewController () <IMAAdsLoaderDelegate, IMAAdsManagerDelegate>
@property(nonatomic) IMAAdsLoader *adsLoader;
@property(nonatomic) IMAAdDisplayContainer *adDisplayContainer;
@property(nonatomic) IMAAdsManager *adsManager;
@property(nonatomic) IMAAVPlayerContentPlayhead *contentPlayhead;
@property(nonatomic) AVPlayerViewController *contentPlayerViewController;
@property(nonatomic, getter=isAdBreakActive) BOOL adBreakActive;
@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor blackColor];
  [self setupAdsLoader];
  [self setupContentPlayer];
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  [self requestAds];
}

- (void)setupAdsLoader {
  self.adsLoader = [[IMAAdsLoader alloc] init];
  self.adsLoader.delegate = self;
}

- (void)setupContentPlayer {
  // Create a content video player. Create a playhead to track content progress so the SDK knows
  // when to play ads in a VMAP playlist.
  NSURL *contentURL = [NSURL URLWithString:kContentURLString];
  AVPlayer *player = [AVPlayer playerWithURL:contentURL];
  self.contentPlayerViewController = [[AVPlayerViewController alloc] init];
  self.contentPlayerViewController.player = player;
  self.contentPlayerViewController.view.frame = self.view.bounds;
  self.contentPlayhead =
      [[IMAAVPlayerContentPlayhead alloc] initWithAVPlayer:self.contentPlayerViewController.player];

  // Track end of content.
  AVPlayerItem *contentPlayerItem = self.contentPlayerViewController.player.currentItem;
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(contentDidFinishPlaying:)
                                               name:AVPlayerItemDidPlayToEndTimeNotification
                                             object:contentPlayerItem];

  // Attach content video player to view hierarchy.
  [self showContentPlayer];
}

// Add the content video player as a child view controller.
- (void)showContentPlayer {
  [self addChildViewController:self.contentPlayerViewController];
  self.contentPlayerViewController.view.frame = self.view.bounds;
  [self.view insertSubview:self.contentPlayerViewController.view atIndex:0];
  [self.contentPlayerViewController didMoveToParentViewController:self];
}

// Remove and detach the content video player.
- (void)hideContentPlayer {
  // The whole controller needs to be detached so that it doesn't capture resume events from the
  // remote and play content underneath the ad.
  [self.contentPlayerViewController willMoveToParentViewController:nil];
  [self.contentPlayerViewController.view removeFromSuperview];
  [self.contentPlayerViewController removeFromParentViewController];
}

- (void)requestAds {
  // Pass the main view as the container for ad display.
  self.adDisplayContainer = [[IMAAdDisplayContainer alloc] initWithAdContainer:self.view
                                                                viewController:self];
  IMAAdsRequest *request = [[IMAAdsRequest alloc] initWithAdTagUrl:kAdTagURLString
                                                adDisplayContainer:self.adDisplayContainer
                                                   contentPlayhead:self.contentPlayhead
                                                       userContext:nil];
  [self.adsLoader requestAdsWithRequest:request];
}

- (void)contentDidFinishPlaying:(NSNotification *)notification {
  // Notify the SDK that the postrolls should be played.
  [self.adsLoader contentComplete];
}

- (void)dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - UIFocusEnvironment

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
  if (self.isAdBreakActive) {
    // Send focus to the ad display container during an ad break.
    return @[ self.adDisplayContainer.focusEnvironment ];
  } else {
    // Send focus to the content player otherwise.
    return @[ self.contentPlayerViewController ];
  }
}

#pragma mark - IMAAdsLoaderDelegate

- (void)adsLoader:(IMAAdsLoader *)loader adsLoadedWithData:(IMAAdsLoadedData *)adsLoadedData {
  // Initialize and listen to the ads manager loaded for this request.
  self.adsManager = adsLoadedData.adsManager;
  self.adsManager.delegate = self;
  [self.adsManager initializeWithAdsRenderingSettings:nil];
}

- (void)adsLoader:(IMAAdsLoader *)loader failedWithErrorData:(IMAAdLoadingErrorData *)adErrorData {
  // Fall back to playing content.
  NSLog(@"Error loading ads: %@", adErrorData.adError.message);
  [self.contentPlayerViewController.player play];
}

#pragma mark - IMAAdsManagerDelegate

- (void)adsManager:(IMAAdsManager *)adsManager didReceiveAdEvent:(IMAAdEvent *)event {
  // Play each ad once it has loaded.
  if (event.type == kIMAAdEvent_LOADED) {
    [adsManager start];
  }
}

- (void)adsManager:(IMAAdsManager *)adsManager didReceiveAdError:(IMAAdError *)error {
  // Fall back to playing content.
  NSLog(@"AdsManager error: %@", error.message);
  [self showContentPlayer];
  [self.contentPlayerViewController.player play];
}

- (void)adsManagerDidRequestContentPause:(IMAAdsManager *)adsManager {
  // Pause the content for the SDK to play ads.
  [self.contentPlayerViewController.player pause];
  [self hideContentPlayer];
  // Trigger an update to send focus to the ad display container.
  self.adBreakActive = YES;
  [self setNeedsFocusUpdate];
}

- (void)adsManagerDidRequestContentResume:(IMAAdsManager *)adsManager {
  // Resume the content since the SDK is done playing ads (at least for now).
  [self showContentPlayer];
  [self.contentPlayerViewController.player play];
  // Trigger an update to send focus to the content player.
  self.adBreakActive = NO;
  [self setNeedsFocusUpdate];
}

@end
