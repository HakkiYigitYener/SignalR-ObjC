source 'https://github.com/CocoaPods/Specs.git'

#use_frameworks!
platform :ios, '8.0'

project 'SignalR.Client.ObjC/SignalR.Client.ObjC.xcodeproj'
workspace 'SignalR.Client.ObjC'

def mandatory_pods
    pod 'AFNetworking', '~> 3.0'
    pod 'SocketRocket'
end

def test_pods
    pod 'OCMock'
    pod 'URLMock', '1.3.2'
end

target 'SignalR.Client.iOS' do
    mandatory_pods
end
target 'SignalR.Client.OSX' do
    mandatory_pods
end

target 'SignalR.Client.iOSTests' do
    mandatory_pods
    test_pods
end
target 'SignalR.Client.OSXTests' do
    mandatory_pods
    test_pods
end

post_install do |installer_representation|
    installer_representation.pods_project.targets.each do |target|
        target.build_configurations.each do |config|
            config.build_settings['ONLY_ACTIVE_ARCH'] = 'NO'
        end
    end
end
