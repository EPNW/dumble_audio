import Flutter
import UIKit
import AVFoundation

@available(iOS 13.0, *)
public class SwiftDumbleAudioPlugin: NSObject, FlutterPlugin, FlutterStreamHandler
{
    
    
  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SwiftDumbleAudioPlugin();
    
    let methodChannel = FlutterMethodChannel(name: "eu.epnw.dumble_audio/audio", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(instance, channel: methodChannel)
    
    let streamChannel = FlutterEventChannel(name: "eu.epnw.dumble_audio/audio_stream", binaryMessenger: registrar.messenger());
    streamChannel.setStreamHandler(instance);
    
  }
    /*self.recordingFormat =
    self.playingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000.0, channels: 1, interleaved: false);*/
    
    private func encoding(flutterValue: Int) -> AVAudioCommonFormat{
        switch flutterValue {
        case 0:
            return .pcmFormatInt16
        case 1:
            return .pcmFormatFloat32
        default:
            return .pcmFormatInt16
        }
    }
    
    
private var audioEngine: AudioEngine?;
    private var eventSink : FlutterEventSink?;
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events;
        return nil;
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        self.eventSink = nil;
        return nil;
    }
  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    var args : Dictionary<String,Any> = [:];
    if call.arguments != nil{
        args = call.arguments as! Dictionary<String,Any>
    }
    if (call.method == "startEngine"){
        guard let recordingEncodingIndex = args["recordingEncoding"] as? Int else{
            result(nil);
            return;
        }
        guard let recordingSampleRate = args["recordingSampleRate"] as? Int else {
            result(nil);
            return;
        }
        guard let recordingChannelCount = args["recordingChannelCount"] as? Int else{
            result(nil);
            return;
        }
        let recordingFormat : AVAudioFormat = AVAudioFormat(commonFormat: encoding(flutterValue: recordingEncodingIndex), sampleRate: Double(recordingSampleRate), channels: AVAudioChannelCount(recordingChannelCount+1) , interleaved: false)!;
            guard let playingEncodingIndex = args["playingEncoding"] as? Int else{
                result(nil);
                return;
            }
            guard let playingSampleRate = args["playingSampleRate"] as? Int else {
                result(nil);
                return;
            }
            guard let playingChannelCount = args["playingChannelCount"] as? Int else{
                result(nil);
                return;
            }
        let playingFormat : AVAudioFormat = AVAudioFormat(commonFormat: encoding(flutterValue: playingEncodingIndex), sampleRate: Double(playingSampleRate), channels: AVAudioChannelCount(playingChannelCount+1) , interleaved: false)!;
        self.startEngine(recordingFormat: recordingFormat, playingFormat: playingFormat);
        result(nil);
    }else if (call.method == "stopEngine"){
        self.stopEngine()
        result(nil);
    }else if (call.method == "setMicrophone"){
        guard let enabled  = args["enabled"] as? Bool else {
            print("Error: Enabled parameter not set");
            result(nil);
            return;
        }
        self.setMicrophone(enabled: enabled);
        result(nil);
    }else if (call.method == "setSpeaker"){
        guard let enabled = args["enabled"] as? Bool else {
            print("Error: Enabled parameter not set");
            result(nil);
            return;
        }
        self.setSpeaker(enabled: enabled);
        result(nil);
    } else if (call.method == "addTarget"){
        guard let targetId = args["targetId"] as? Int else {
            print("Error: TargetId parameter not set");
            result(nil);
            return;
        }
        self.addTarget(targetId: targetId);
        result(nil);
    }else if (call.method == "removeTarget"){
        guard let targetId = args["targetId"] as? Int else {
            print("Error: TargetId parameter not set");
            result(nil);
            return;
        }
        self.removeTarget(targetId: targetId);
        result(nil);
    }else if (call.method == "scheduleBuffer"){
        guard let targetId = args["targetId"] as? Int else {
            print("Error: TargetId parameter not set");
            result(nil);
            return;
        }
        guard let buffer = args["buffer"] as? FlutterStandardTypedData else {
            print("Error: Buffer parameter not set");
            result(nil);
            return;
        }
        self.scheduleBuffer(targetId: targetId, buffer: buffer)
        result(nil);
    }
  }
    
    private func startEngine(recordingFormat: AVAudioFormat, playingFormat: AVAudioFormat){
        if self.audioEngine != nil{
            print("Error: Audio Engine already started");
            return;
        } else {
            self.audioEngine = AudioEngine(recordingFormat: recordingFormat,playingFormat:playingFormat,recordingCallback: self.recordingCallback)
        }
        
    }
    private func stopEngine(){
        guard let engine = self.audioEngine else {
            print("Error: Audio Engine not started");
            return;
        }
        engine.stopEngine();
        self.audioEngine = nil;
    }
    private func setMicrophone(enabled: Bool){
        guard let engine = self.audioEngine else {
            print("Error: Audio Engine not started");
            return;
        }
        engine.isRecording = enabled;
    }
    private func setSpeaker(enabled:Bool){
        guard let engine = self.audioEngine else {
            print("Error: Audio Engine not started");
            return;
        }
        engine.setSpeaker(enabled: enabled);
    }
    private func addTarget(targetId: Int){
        guard let engine = self.audioEngine else {
            print("Error: Audio Engine not started");
            return;
        }
        engine.addTarget(targetId: targetId);
    }
    private func removeTarget(targetId: Int){
        guard let engine = self.audioEngine else {
            print("Error: Audio Engine not started");
            return;
        }
        engine.removeTarget(targetId: targetId);
    }
    private func scheduleBuffer(targetId: Int, buffer: FlutterStandardTypedData){
        guard let engine = self.audioEngine else {
            print("Error: Audio Engine not started");
            return;
        }
        engine.scheduleBuffer(targetId: targetId, buffer: flutterDataToData(data: buffer))
    }
    
    private func recordingCallback(buffer: Data){
        guard let events = self.eventSink else {
            return;
        }
        events(self.dataToFlutterData(data: buffer));
    }

    private func dataToFlutterData(data: Data )-> FlutterStandardTypedData {
        return FlutterStandardTypedData(bytes: data);
    }
    private func flutterDataToData (data: FlutterStandardTypedData) -> Data {
        return data.data;
    }
}
