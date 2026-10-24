//
//  LineriOS-Bridging-Header.h
//  LineriOS
//
//  Objective-C Bridging Header for Spotify iOS SDK (SPTAppRemote).
//

#ifndef LineriOS_Bridging_Header_h
#define LineriOS_Bridging_Header_h

#import <Foundation/Foundation.h>

#if __has_include(<SpotifyiOS/SpotifyiOS.h>)
#import <SpotifyiOS/SpotifyiOS.h>
#elif __has_include("SpotifyiOS.h")
#import "SpotifyiOS.h"
#endif

#endif /* LineriOS_Bridging_Header_h */
