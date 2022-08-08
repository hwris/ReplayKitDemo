Pod::Spec.new do |s|
  s.name             = 'SYScreenRecorder'
  s.version          = '0.1.0'
  s.summary          = 'A record screen library base in AirPlay or ReplayKit'
  s.description      = <<-DESC
  A record screen library base in AirPlay or ReplayKit.
  DESC

  s.homepage         = 'http://github.com/hwris/ReplayKitDemo'
  s.license          = { :type => 'MIT' }
  s.author           = { 'suyang' => 'abb416165@gmail.com' }
  s.source           = { :git => 'http://github.com/hwris/ReplayKitDemo', :tag => s.version.to_s }

  s.ios.deployment_target = '9.0'
  s.source_files = 'Replaykit/Classes/**/*.{h,m}'
  s.frameworks = 'AVFoundation'
  s.dependency 'CocoaAsyncSocket'
end
