#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'voice_activity_detector'
  s.version          = '0.0.1'
  s.summary          = 'WebRTC based voice activity detection.'
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files        = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'

  s.ios.deployment_target = '9.3'
  s.swift_version = "4.0"
  s.dependency 'VoiceActivityDetector'
  s.dependency 'DownloadingFileAsset'
end
