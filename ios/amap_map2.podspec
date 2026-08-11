#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint amap_map2.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'amap_map2'
  s.version          = '1.0.1'
  s.summary          = 'A Flutter plugin for AMap.'
  s.description      = <<-DESC
A Flutter plugin for AMap SDK on Android and iOS.
                       DESC
  s.homepage         = 'https://github.com/wubostc/amap_map'
  s.license          = { :type => 'Apache License, Version 2.0', :file => '../LICENSE' }
  s.author           = { 'wubostc' => '913721086@qq.com' }
  s.source           = { :git => 'https://github.com/wubostc/amap_map.git', :tag => 'v1.0.1' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'AMap3DMap', '11.2.000'
  s.static_framework = true
  s.platform = :ios, '12.0'

  s.static_framework = true
  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
