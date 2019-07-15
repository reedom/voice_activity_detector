#import "VoiceActivityDetectorPlugin.h"
#import <voice_activity_detector/voice_activity_detector-Swift.h>

@implementation VoiceActivityDetectorPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftVoiceActivityDetectorPlugin registerWithRegistrar:registrar];
}
@end
