#import "DumbleAudioPlugin.h"
#if __has_include(<dumble_audio/dumble_audio-Swift.h>)
#import <dumble_audio/dumble_audio-Swift.h>
#else
// Support project import fallback if the generated compatibility header
// is not copied when this plugin is created as a library.
// https://forums.swift.org/t/swift-static-libraries-dont-copy-generated-objective-c-header/19816
#import "dumble_audio-Swift.h"
#endif

@implementation DumbleAudioPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftDumbleAudioPlugin registerWithRegistrar:registrar];
}
@end
