//
//  VideoView.swift
//  native_video_view
//
//  Created by Luis Jara Castillo on 11/4/19.
//

import UIKit
import AVFoundation

extension String {
    subscript(_ range: CountableRange<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
        let end = index(start, offsetBy: min(self.count - range.lowerBound,
                                             range.upperBound - range.lowerBound))
        return String(self[start..<end])
    }

    subscript(_ range: CountablePartialRangeFrom<Int>) -> String {
        let start = index(startIndex, offsetBy: max(0, range.lowerBound))
         return String(self[start...])
    }
}

struct DRMSource: Decodable {
    let srcURL: String
    let licenseAcquisitionURL: String
    let certificateURL: String
    let contentId: String
}

class VideoView : UIView {
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var videoAsset: AVAsset?
    private var initialized: Bool = false
    private var onPrepared: (()-> Void)? = nil
    private var onFailed: ((String) -> Void)? = nil
    private var onCompletion: (() -> Void)? = nil
    private static let queue = DispatchQueue(label: "Some queue")
    private var resourceLoaderDelegate: FairPlayAssetResourceLoaderDelegate?
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
    }
    
    deinit {
        self.removeOnFailedObserver()
        self.removeOnPreparedObserver()
        self.removeOnCompletionObserver()
        self.player?.currentItem?.removeObserver(self, forKeyPath: "status")
        NotificationCenter.default.removeObserver(self)
        self.stop()
        self.initialized = false
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.configureVideoLayer()
    }
    
    func configure(videoPath: String?, isURL: Bool, drmLicenseUrl: String?, drmCertificateUrl: String?, contentId: String?){
        if !initialized {
            self.initVideoPlayer()
        }
        if let path = videoPath {
            if isURL && drmLicenseUrl != nil && drmCertificateUrl != nil {
                print("🍄 Load fairplay url drmLicenseUrl:" + drmLicenseUrl!)
                let asset = AVURLAsset(url: URL(string:path)!);
                
                let resourceLoaderDelegate = FairPlayAssetResourceLoaderDelegate(
                    certificateURL: URL(string:drmCertificateUrl!)!,
                    licenseAcquisitionURL: URL(string:drmLicenseUrl!)!,
                    contentId: contentId ?? "irdeto"
                )
                self.resourceLoaderDelegate = resourceLoaderDelegate
                asset.resourceLoader.setDelegate(resourceLoaderDelegate, queue: Self.queue)
                
                let item = AVPlayerItem(asset: asset)
                player?.replaceCurrentItem(with: item)
                self.videoAsset = asset
                self.configureVideoLayer()
                // Notifies when the video finishes playing.
                NotificationCenter.default.addObserver(self, selector: #selector(onVideoCompleted(notification:)), name: .AVPlayerItemDidPlayToEndTime, object: self.player?.currentItem)
                
                item.addObserver(self, forKeyPath: "status", options: [.old, .new], context: nil)
                
            } else {
                let uri: URL? = isURL ? URL(string: path) : URL(fileURLWithPath: path)
                let asset = AVAsset(url: uri!)
                let item = AVPlayerItem(asset: asset)
                player?.replaceCurrentItem(with: item)
                self.videoAsset = asset
                self.configureVideoLayer()
                // Notifies when the video finishes playing.
                NotificationCenter.default.addObserver(self, selector: #selector(onVideoCompleted(notification:)), name: .AVPlayerItemDidPlayToEndTime, object: self.player?.currentItem)
                
                item.addObserver(self, forKeyPath: "status", options: [.old, .new], context: nil)
            }
        }
    }
    
    private func configureVideoLayer(){
        playerLayer = AVPlayerLayer(player: player)
        playerLayer?.frame = bounds
        playerLayer?.videoGravity = .resize
        if let playerLayer = self.playerLayer {
            self.clearSubLayers()
            layer.addSublayer(playerLayer)
        }
    }
    
    private func clearSubLayers(){
        layer.sublayers?.forEach{
            $0.removeFromSuperlayer()
        }
    }
    
    private func initVideoPlayer() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
        } catch {
        }
        self.player = AVPlayer(playerItem: nil)
        self.initialized = true
    }
    
    func play(){
        if !self.isPlaying() && self.videoAsset != nil {
            print("play","start");
            self.player?.play()
        } else if self.videoAsset == nil {
            print("play failed", "self.videoAsset == nil");
        } else {
            print("play failed", "already playing");
        }
    }
    
    func pause(restart:Bool){
        self.player?.pause()
        if(restart){
            self.player?.seek(to: CMTime.zero)
        }
    }
    
    func stop(){
        self.pause(restart: true)
    }
    
    func isPlaying() -> Bool{
        return self.player?.rate != 0 && self.player?.error == nil
    }

    func setVolume(volume:Double){
        self.player?.volume = Float(volume)
    }
    
    func getDuration()-> Int64 {
        if isDurationIndefinite() {return -1}
        let durationObj = self.player?.currentItem?.asset.duration
        return self.transformCMTime(time: durationObj)
    }
    
    func isDurationIndefinite() -> Bool {
        guard let durationObj = self.player?.currentItem?.asset.duration else { return true }
        return CMTIME_IS_INDEFINITE(durationObj)
    }
    
    func getCurrentPosition() -> Int64 {
        let currentTime = self.player?.currentItem?.currentTime()
        return self.transformCMTime(time: currentTime)
    }
    
    func getVideoHeight() -> Double {
        var height: Double = 0.0
        let videoTrack = self.getVideoTrack()
        if videoTrack != nil {
            height = Double(videoTrack?.naturalSize.height ?? 0.0)
        }
        return height
    }
    
    func getVideoWidth() -> Double {
        var width: Double = 0.0
        let videoTrack = self.getVideoTrack()
        if videoTrack != nil {
            width = Double(videoTrack?.naturalSize.width ?? 0.0)
        }
        return width
    }
    
    func getVideoTrack() -> AVAssetTrack? {
        var videoTrack: AVAssetTrack? = nil
        let tracks = videoAsset?.tracks(withMediaType: .video)
        if tracks != nil && tracks!.count > 0 {
            videoTrack = tracks![0]
        }
        return videoTrack
    }
    
    private func transformCMTime(time:CMTime?) -> Int64 {
        var ts : Double = 0
        if let obj = time {
            ts = CMTimeGetSeconds(obj) * 1000
        }
        return Int64(ts)
    }
    
    func seekTo(positionInMillis: Int64?){
        if let pos = positionInMillis {
            self.player?.seek(to: CMTimeMake(value: pos, timescale: 1000), toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero)
        }
    }
    
    func addOnPreparedObserver(callback: @escaping ()->Void){
        self.onPrepared = callback
    }
    
    func removeOnPreparedObserver() {
        self.onPrepared = nil
    }
    
    private func notifyOnPreaparedObserver(){
        if onPrepared != nil {
            self.onPrepared!()
        }
    }
    
    func addOnFailedObserver(callback: @escaping (String)->Void){
        self.onFailed = callback
    }
    
    func removeOnFailedObserver() {
        self.onFailed = nil
    }
    
    private func notifyOnFailedObserver(message: String){
        if onFailed != nil {
            self.onFailed!(message)
        }
    }
    
    func addOnCompletionObserver(callback: @escaping ()->Void){
        self.onCompletion = callback
    }
    
    func removeOnCompletionObserver() {
        self.onCompletion = nil
    }
    
    private func notifyOnCompletionObserver(){
        if onCompletion != nil {
            self.onCompletion!()
        }
    }
    
    @objc func onVideoCompleted(notification:NSNotification){
        self.notifyOnCompletionObserver()
    }
    
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "status" {
            let item = object as? AVPlayerItem
            var status = AVPlayerItem.Status.failed;
            if item != nil {
                status = item!.status;
            }
            switch(status) {
            case .readyToPlay:
                print("👍","Status readyToPlay")
                self.notifyOnPreaparedObserver()
                break
            case .failed:
                if let error = item?.error{
                    let errorMessage = error.localizedDescription
                    print("😵","Status failed", errorMessage);
                    self.notifyOnFailedObserver(message: errorMessage)
                }
                break
             default:
                print("🙄","Status unknown")
                break
            }
        } else {
            print("🙄","keyPath not implemented", keyPath as Any)
        }
    }
}



class FairPlayAssetResourceLoaderDelegate: NSObject, AVAssetResourceLoaderDelegate {
    let certificateURL: URL
    let licenseAcquisitionURL: URL
    let contentId: String

    init(certificateURL: URL, licenseAcquisitionURL: URL, contentId: String) {
        self.certificateURL = certificateURL
        self.licenseAcquisitionURL = licenseAcquisitionURL
        self.contentId = contentId
    }

    public func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        print(loadingRequest.request.url ?? "no url")

        // We first check if a url is set in the manifest.
        guard let url = loadingRequest.request.url else {
            print("🔑*", #function, "Unable to read the url/host data.")
            loadingRequest.finishLoading(with: NSError(domain: "com.icapps.error", code: -1, userInfo: nil))
            return false
        }
        print("🔑 resourceLoader url", #function, url)
        print("🔑 resourceLoader certificateURL", #function, certificateURL)
        // When the url is correctly found we try to load the certificate data. Watch out! For this
        // example the certificate resides inside the bundle. But it should be preferably fetched from
        // the server.
        let certificateData2:Data?
        do {
            certificateData2 = try getDataRequest2(url: certificateURL)
        } catch let error {
            print(error)
            print("🔑", #function, "Unable to read certificateData data!")
            loadingRequest.finishLoading(with: NSError(domain: "com.icapps.error", code: -2, userInfo: nil))
            return false
        }
        let certificateData = certificateData2!

        //guard let certificateData = try? Data(contentsOf: certificateURL) else {
        //    print("🔑", #function, "Unable to read certificateData data!")
        //    loadingRequest.finishLoading(with: NSError(domain: "com.icapps.error", code: -2, userInfo: nil))
        //    return false
        //}

        // Request the Server Playback Context.
        let usedContentId = self.contentId
        guard
            let contentIdData = usedContentId.data(using: String.Encoding.utf8),
            let spcData = try? loadingRequest.streamingContentKeyRequestData(forApp: certificateData, contentIdentifier: contentIdData, options: nil),
            let dataRequest = loadingRequest.dataRequest else {
                print("🔑* resourceLoader", #function, "Unable to read the SPC data.")
                loadingRequest.finishLoading(with: NSError(domain: "com.icapps.error", code: -3, userInfo: nil))
                return false
            }
        print("🔑 resourceLoader ckcURL", #function, licenseAcquisitionURL)
        // Request the Content Key Context from the Key Server Module.
        let ckcURL = licenseAcquisitionURL
        var request = URLRequest(url: ckcURL)
        request.httpMethod = "POST"
        request.httpBody = spcData
        let session = URLSession(configuration: URLSessionConfiguration.default)
        let task = session.dataTask(with: request) { data, response, error in
            if let data = data {
                print("🔑 resourceLoader data", #function, data)
                // The CKC is correctly returned and is now send to the `AVPlayer` instance so we
                // can continue to play the stream.
                dataRequest.respond(with: data)
                loadingRequest.finishLoading()
            } else {
                print("🔑* resourceLoader", #function, "Unable to fetch the CKC.")
                loadingRequest.finishLoading(with: NSError(domain: "com.icapps.error", code: -4, userInfo: nil))
            }
        }
        task.resume()
        // asdf
        return true
    }

    public func getDataRequest(url: URL) throws -> Data {
          let certificateData2:Data?
            do {
                print("the url string = \(url.absoluteString)")
                print("👍", #function, "Url: read certificateData data!", url)
                certificateData2 = try Data(contentsOf: url)
                print("🔑", #function, "Success: read certificateData data!")
            } catch let error {
                print(error)
                print("🔑", #function, "Failed: Unable to read certificateData data!")
                throw error;
            }
            return certificateData2!;
        }

    public func getDataRequest2(url: URL) throws -> Data {
        let certificateData2:Data?
        
        let request1: NSURLRequest = NSURLRequest(url: url)
        let response: AutoreleasingUnsafeMutablePointer<URLResponse?>? = nil
        
        do{
            certificateData2 = try NSURLConnection.sendSynchronousRequest(request1 as URLRequest, returning: response)
            print("🔑", #function, "Success: read certificateData data!")
        } catch let error
        {
            print(error)
            print("🔑", #function, "Failed: Unable to read certificateData data!")
            throw error;
        }
        return certificateData2!;
    }

    
}
