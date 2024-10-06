//
//  Audio.swift
//  Selected
//
//  Created by sake on 2024/6/10.
//

import Foundation
import SwiftUI
import DSWaveformImageViews


struct ProgressWaveformView: View {
    let audioURL: URL
    let progress: Binding<Double>

    var body: some View {
        GeometryReader { geometry in
            WaveformView(audioURL: audioURL) { shape in
                shape.fill(.clear)
                shape.fill(.blue).mask(alignment: .leading) {
                    Rectangle().frame(width: geometry.size.width * progress.wrappedValue)
                }
            }
        }
    }
}


struct AudioPlayerView: View {
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var sliderValue: Double = 0.0

    let audioURL: URL
    @State var progress: Double = 0

    var body: some View {
        HStack {
            Text(String(format: "%02d:%02d", ((Int)((audioPlayer.currentTime))) / 60, ((Int)((audioPlayer.currentTime))) % 60))
                .foregroundColor(Color.black.opacity(0.6))
                .font(.custom("Quicksand Regular", size: 14))
                .frame(width: 40).padding(.leading, 10)

            ZStack{
                ProgressWaveformView(audioURL: audioURL, progress: $progress).frame(width: 400)
                Slider(value: $sliderValue, in: 0...audioPlayer.duration) { isEditing in
                    if !isEditing {
                        audioPlayer.seek(to: sliderValue)
                    }
                }.foregroundColor(.clear).background(.clear).opacity(0.1)
                    .controlSize(.mini).frame(width: 400)
                    .onChange(of: audioPlayer.currentTime) { newValue in
                        sliderValue = newValue
                        progress = sliderValue/audioPlayer.duration
                    }.frame(width: 300)
            }.frame(height: 30)

            Text(String(format: "%02d:%02d", ((Int)((audioPlayer.duration-audioPlayer.currentTime))) / 60, ((Int)((audioPlayer.duration-audioPlayer.currentTime))) % 60))
                .foregroundColor(Color.black.opacity(0.6))
                .font(.custom("Quicksand Regular", size: 14))
                .frame(width: 40)

            BarButton(icon: "symbol:gobackward.5", title: "" , clicked: {
                $isLoading in
                var val = sliderValue - 15
                if val < 0 {
                    val = 0
                }
                sliderValue = val
                audioPlayer.seek(to: sliderValue)
            }).frame(height: 30).cornerRadius(5)

            BarButton(icon: "symbol:goforward.5", title: "" , clicked: {
                $isLoading in
                var val = sliderValue + 15
                if val > audioPlayer.duration {
                    val = audioPlayer.duration
                }
                sliderValue = val
                audioPlayer.seek(to: sliderValue)
                if  val == audioPlayer.duration {
                    audioPlayer.pause()
                }
            }).frame(height: 30).cornerRadius(5)

            BarButton(icon: audioPlayer.isPlaying ? "symbol:pause.fill" : "symbol:play.fill", title: "" , clicked: {
                $isLoading in
                audioPlayer.isPlaying ? audioPlayer.pause() : audioPlayer.play()
            }).frame(height: 30).cornerRadius(5)

            BarButton(icon: "symbol:square.and.arrow.down", title: "" , clicked: {
                $isLoading in
                audioPlayer.pause()
                audioPlayer.save(audioURL)
            }).frame(height: 30).cornerRadius(5)
            Spacer()
        }.frame(height: 50)
            .background(.white)
            .cornerRadius(5).fixedSize()
            .onAppear() {
                audioPlayer.loadAudio(url: audioURL)
                audioPlayer.play()
            }
    }
}


import AVFoundation

class AudioPlayer: ObservableObject, @unchecked Sendable {
    private var player: AVAudioPlayer?
    @Published var isPlaying: Bool = false
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0

    private var timer: Timer?

    func loadAudio(url: URL) {
        do {
            player = try AVAudioPlayer(contentsOf: url)
            duration = player?.duration ?? 0.0
        } catch {
            print("Error loading audio file: \(error)")
        }
    }

    func play() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.isPlaying =  self.player?.isPlaying ?? false
            if self.isPlaying {
                self.currentTime = self.player?.currentTime ?? 0.0
            } else {
                stopTimer()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
        currentTime = time
    }

    func save(_ audioURL: URL) {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let documentsDirectory = paths.first else{
            return
        }
        let unixTime = Int(Date().timeIntervalSince1970)
        let tts = documentsDirectory.appending(path: "Selected/tts-\(unixTime).mp3")
        do{
            try FileManager.default.createDirectory(at: tts.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: audioURL, to: tts)
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: tts.deletingLastPathComponent().path)
        } catch {
            NSLog("move failed \(error)")
        }
    }
}
