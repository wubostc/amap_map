package com.amap.flutter.map2;

import androidx.annotation.NonNull;
import androidx.lifecycle.Lifecycle;

import com.amap.flutter.map2.utils.LogUtil;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.embedding.engine.plugins.lifecycle.FlutterLifecycleAdapter;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodChannel;

/**
 * AmapFlutterMapPlugin
 */
public class AMapFlutterMapPlugin implements
        FlutterPlugin,
        ActivityAware {
    private static final String CLASS_NAME = "AMapFlutterMapPlugin";
    private static final String VIEW_TYPE = "com.amap.flutter.map2";
    private Lifecycle lifecycle;
    private FlutterPluginBinding pluginBinding;
    private AMapServicesController servicesController;
    private MethodChannel locationChannel;
    private MethodChannel geocodingChannel;
    private EventChannel locationEventChannel;

    public AMapFlutterMapPlugin() {
    }

    // FlutterPlugin

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        LogUtil.i(CLASS_NAME, "onAttachedToEngine==>");
        this.pluginBinding = binding;
        servicesController = new AMapServicesController(binding.getApplicationContext());
        locationChannel = new MethodChannel(binding.getBinaryMessenger(), "amap_map2/location");
        geocodingChannel = new MethodChannel(binding.getBinaryMessenger(), "amap_map2/geocoding");
        locationEventChannel = new EventChannel(binding.getBinaryMessenger(), "amap_map2/location_events");
        locationChannel.setMethodCallHandler(servicesController);
        geocodingChannel.setMethodCallHandler(servicesController);
        locationEventChannel.setStreamHandler(servicesController);
        binding
                .getPlatformViewRegistry()
                .registerViewFactory(
                        VIEW_TYPE,
                        new AMapPlatformViewFactory(
                                binding.getBinaryMessenger(),
                                () -> lifecycle));
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        LogUtil.i(CLASS_NAME, "onDetachedFromEngine==>");
        locationChannel.setMethodCallHandler(null);
        geocodingChannel.setMethodCallHandler(null);
        locationEventChannel.setStreamHandler(null);
        servicesController.dispose();
        servicesController = null;
        locationChannel = null;
        geocodingChannel = null;
        locationEventChannel = null;
        pluginBinding = null;
    }


    // ActivityAware

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        LogUtil.i(CLASS_NAME, "onAttachedToActivity==>");
        lifecycle = FlutterLifecycleAdapter.getActivityLifecycle(binding);
        pluginBinding.getPlatformViewRegistry().registerViewFactory(
                VIEW_TYPE,
                new AMapPlatformViewFactory(
                        pluginBinding.getBinaryMessenger(),
                        () -> lifecycle
                )
        );
    }

    @Override
    public void onDetachedFromActivity() {
        LogUtil.i(CLASS_NAME, "onDetachedFromActivity==>");
        lifecycle = null;
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        LogUtil.i(CLASS_NAME, "onReattachedToActivityForConfigChanges==>");
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        LogUtil.i(CLASS_NAME, "onDetachedFromActivityForConfigChanges==>");
        this.onDetachedFromActivity();
    }
}
