//
//  AudioEngine.swift
//  dumble_audio
//
//  Created by Nils Wieler on 26.04.21.
//

import AVFoundation
import Foundation


@available(iOS 13.0, *)
class AudioEngine {
    
    private var avEngine : AVAudioEngine?;
    private var avSession : AVAudioSession?;
    private var mainMixer : AVAudioMixerNode?;
    private var playingFormat:AVAudioFormat;
    private var recordingFormat : AVAudioFormat;
    private var recordingCallback : (Data) -> ();
    
    private var targets : [Int:AVAudioPlayerNode] = [:]
    
    public var isRecording : Bool = false;
    
    init(recordingFormat: AVAudioFormat, playingFormat: AVAudioFormat,recordingCallback: @escaping (Data) -> ()) {
        self.recordingFormat = recordingFormat;
        self.playingFormat = playingFormat;
        self.recordingCallback = recordingCallback;
        startEngine();
    }
    deinit {
        stopEngine();
    }
    
    
    
    private func startEngine(){
        setupSession();
        registerForNotifications();
        setupEngine();
    }
    public func stopEngine(){
        disposeEngine();
        deactivateSession();
        unregisterForNotifications();
    }
    
    public func setSpeaker(enabled:Bool){
        guard let session = self.avSession else {
            return;
        }
        do {
            if(enabled){
                try session.overrideOutputAudioPort(.speaker);
            }else {
                try session.overrideOutputAudioPort(.none);
            }
            
        } catch  {
            print("Error: AudioSession could override output port");
            return;
        }
    }
    
    private func setupSession(){
        self.avSession = AVAudioSession.sharedInstance();
        
        guard let session = self.avSession else {
            print("Error: AudioSession could not be fetched");
            return;
        }
        
        // Setting category PlayAndRecord
        do {
            try session.setCategory(.playAndRecord);
        } catch
        {
            print("Error: AudioSession could not set category");
            return;
        }
        
        // Setting mode VoiceChat
        do {
            try session.setMode(.voiceChat);
        }catch{
            print("Error: AudioSession could not set mode");
            return;
        }
        
        // Set Sample rate 16khz --> if not possible no big issue
        /*do {
         try session.setPreferredSampleRate(16000.0);
         }catch{
         print("Error: AudioSession could not set preferred sample rate");
         }
         
         
         
         // Set IOBufferDuration (0.02s) --> not that big issue
         do {
         try session.setPreferredIOBufferDuration(0.01)
         }catch{
         print("Error: AudioSession could not set preferred buffer duration");
         }*/
        
        
        // Set Session active
        do {
            try session.setActive(true);
        }catch{
            print("Error: AudioSession could not be activated");
            return;
        }
        
    }
    private func deactivateSession(){
        guard  let session = self.avSession else {
            return;
        }
        do {
            try session.setActive(false);
        } catch  {
            print("Error: AudioSession could not be deactivated");
            return;
        }
        self.avSession = nil;
    }
    // Call after setup session
    private func registerForNotifications(){
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: self.avSession)
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChanged), name: AVAudioSession.routeChangeNotification, object: self.avSession)
    }
    private func unregisterForNotifications(){
        NotificationCenter.default.removeObserver(self);
    }
    @objc func handleInterruption(notification: Notification){
        guard let userInfo = notification.userInfo, let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return;
        }
        switch type {
        case .began:
            // An interruption begain.
            //TODO: Notify FLutter that interupption has began
            break
        case .ended:
            // An interruption ended.
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {return}
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            var shouldResume = false;
            if options.contains(.shouldResume){
                shouldResume = true;
            }
        //TODO: Notify FLutter that interupption has ended with should resume
        default:()
            
        }
    }
    
    @objc func handleRouteChanged(notification: Notification){
        guard let userInfo = notification.userInfo, let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt, let reason = AVAudioSession.RouteChangeReason(rawValue:reasonValue) else {
            return;
        }
        //TODO: handle more routeChanges?
        switch reason {
        case .newDeviceAvailable:
            //TODO: Inform Flutter that new device is available
            break
        case .oldDeviceUnavailable:
            //TODO: Inform Flutter that old device is unavialable
            break;
        default: ()
        }
        
    }
    
    private func setupEngine(){
        self.avEngine = AVAudioEngine()
        guard let engine = self.avEngine else {
            print("Error: AVEngine could not be fetched");
            return;
        }
        self.mainMixer = engine.mainMixerNode;
        guard let mixer = self.mainMixer else {
            print("Error: AVEngine could not fetch main mixer");
            return;
        }
        
        let input = engine.inputNode;
        do {
            try input.setVoiceProcessingEnabled(true)
        }catch {
            print("Error: AVEngine could not enable voice processing");
            return;
        }
        let output = engine.outputNode;
        do {
            try output.setVoiceProcessingEnabled(true)
        } catch{
            print("Error: AVEngine could not enable voice processing");
            return;
        }
        let hardwareFormat = input.outputFormat(forBus: 0);
        
        let converter = AVAudioConverter(from: hardwareFormat, to: recordingFormat)!;
        
        let inputSink = AVAudioSinkNode() {(timestamp,frames,audioBufferList) -> OSStatus in
            if self.isRecording {
                let data = Data(bytes: audioBufferList.pointee.mBuffers.mData!, count: Int(audioBufferList.pointee.mBuffers.mDataByteSize))
                
                let buffer = self.dataToPCMBuffer(data: data, format: hardwareFormat);
                let convertedBuffer = AVAudioPCMBuffer(pcmFormat: self.recordingFormat, frameCapacity: buffer.frameCapacity)!
                var hasData = true;
                converter.convert(to: convertedBuffer, error: nil, withInputFrom: {
                    (_,outStatus) -> AVAudioBuffer? in
                    if hasData {
                        outStatus.pointee = .haveData
                        hasData = false;
                        return buffer;
                    }else {
                        outStatus.pointee = .noDataNow
                        return nil;
                    }
                })
                self.recordingCallback(self.pcmBufferToData(buffer: convertedBuffer));
            }
            return noErr
        }
        
        engine.attach(inputSink);
        
        engine.connect(input, to: inputSink, format: nil);
        engine.connect(mixer, to: output, format: nil);
        engine.prepare();
        if !engine.isRunning{
            do{
                try engine.start();
            } catch {
                print("Error: AVEngine could not be started");
                return;
            }
        }
    }
    
    private func disposeEngine(){
        guard let engine = self.avEngine else {
            return;
        }
        engine.stop();
        self.targets.forEach{ key,value in
            engine.detach(value);
        }
        self.targets = [:]
        self.avEngine = nil;
        
    }
    public func addTarget(targetId: Int){
        if self.targets[targetId] != nil {
            return;
        }
        guard let engine = self.avEngine else {
            return;
        }
        guard let mixer = self.mainMixer else {
            return;
        }
        let target = AVAudioPlayerNode();
        engine.attach(target);
        engine.connect(target, to: mixer, format: self.playingFormat);
        target.play();
        self.targets[targetId] = target;
    }
    
    public func removeTarget(targetId: Int){
        guard let target = self.targets[targetId] else {
            return;
        }
        guard let engine = self.avEngine else {
            return;
        }
        target.stop();
        engine.detach(target);
        self.targets.removeValue(forKey: targetId);
    }
    
    public func scheduleBuffer(targetId: Int,buffer: Data){
        guard let target = self.targets[targetId] else  {
            return;
        }
        guard let engine = self.avEngine else {
            return;
        }
        if engine.isRunning {
            let buffer = dataToPCMBuffer(data:buffer,format:self.playingFormat)
            target.scheduleBuffer(buffer, at: nil);
        }
    }
    
    private func dataToPCMBuffer(data:Data,format:AVAudioFormat) -> AVAudioPCMBuffer{
        // It is assumed that channel count is 1
        let nsData = data as NSData;
        let buffer : AVAudioPCMBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: UInt32(nsData.length) / format.streamDescription.pointee.mBytesPerFrame)!;
        buffer.frameLength = buffer.frameCapacity;
        let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: Int(buffer.format.channelCount))
        
        nsData.getBytes(UnsafeMutableRawPointer(channels[0]), length: nsData.length);
        return buffer;
    }
    private func pcmBufferToData(buffer:AVAudioPCMBuffer) -> Data{
        let audioBuffer = buffer.audioBufferList.pointee.mBuffers
        let data = Data(bytes: audioBuffer.mData!, count: Int(audioBuffer.mDataByteSize));
        //let data = Data(bytes: audioBuffer.mData!, count: 1280);
        return data;
    }
    /*    private func pcmBufferToData(buffer:AVAudioPCMBuffer) -> Data {
     // It is assumed that channel count is 1
     let channels = UnsafeBufferPointer(start: buffer.floatChannelData, count: Int(buffer.format.channelCount));
     let nsData = NSData(bytes: channels[0], length: Int(buffer.frameCapacity*buffer.format.streamDescription.pointee.mBytesPerFrame))
     return (nsData as Data);
     }*/
}
