xcodeproj 'SignalR.Client.ObjC/SignalR.Client.ObjC'
workspace 'SignalR.Client.ObjC'

target "SignalR.Client.iOS" do
    platform :ios, '8.0'
    
    pod 'SocketRocket', '0.4.2'
    
    target "SignalR.Client.iOSTests" do
        pod 'OCMock'
    end
end

target :"SignalR.Client.OSX" do
    platform :osx, '10.9'
    
    pod 'SocketRocket', '0.4.2'
    
    target :"SignalR.Client.OSXTests" do
        pod 'OCMock'
    end
end
