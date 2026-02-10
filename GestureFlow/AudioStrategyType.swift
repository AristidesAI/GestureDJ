//
//  AudioStrategyType.swift
//  GestureFlow
//
//  Created by aristides lintzeris on 10/2/2026.
//


import Foundation
import AVFoundation

enum AudioStrategyType {
    case local, appleMusic, spotify
}
class AudioManager {
    private var localStrategy: LocalAudioStrategy?
    private var currentStrategy: AudioStrategy?
    
    var isTrackLoaded: Bool {
        return currentStrategy != nil
    }

    func loadTrack(url: URL, strategy type: AudioStrategyType) {
        // Stop current if any
        currentStrategy?.stop()
        
        switch type {
        case .local:
            if localStrategy == nil {
                localStrategy = LocalAudioStrategy()
            }
            currentStrategy = localStrategy
            currentStrategy?.play(trackURL: url)
        case .appleMusic:
            // TODO: Implement MPMediaStrategy
            print("Apple Music not yet implemented.")
        case .spotify:
            // TODO: Implement SpotifyStrategy
            print("Spotify not yet implemented.")
        }
    }
    
    func play() {
        currentStrategy?.resume()
    }
    
    func pause() {
        currentStrategy?.pause()
    }
    
    func restart() {
        currentStrategy?.restart()
    }
    
    // DSP controls are passed through to the current strategy.
    func setSpeed(_ speed: Float) {
        currentStrategy?.setSpeed(speed)
    }
    
    func setPitch(_ pitch: Float) {
        currentStrategy?.setPitch(pitch)
    }
    
    func setVolume(_ volume: Float) {
        currentStrategy?.setVolume(volume)
    }
    
    func getMainMixerNode() -> AVAudioNode? {
        return currentStrategy?.getMainMixerNode()
    }
}