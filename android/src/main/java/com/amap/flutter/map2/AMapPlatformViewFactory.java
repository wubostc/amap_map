package com.amap.flutter.map2;

import android.content.Context;

import androidx.lifecycle.LifecycleOwner;

import com.amap.api.maps.model.CameraPosition;
import com.amap.flutter.map2.utils.ConvertUtil;
import com.amap.flutter.map2.utils.LogUtil;

import java.util.Collections;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

/**
 * @author whm
 * @date 2020/10/27 4:08 PM
 * @mail hongming.whm@alibaba-inc.com
 * @since
 */
class AMapPlatformViewFactory extends PlatformViewFactory {
    private static final String CLASS_NAME = "AMapPlatformViewFactory";
    private final BinaryMessenger binaryMessenger;
    private final LifecycleOwner lifecycleProvider;

    AMapPlatformViewFactory(BinaryMessenger binaryMessenger,
                            LifecycleOwner lifecycleProvider) {
        super(StandardMessageCodec.INSTANCE);
        this.binaryMessenger = binaryMessenger;
        this.lifecycleProvider = lifecycleProvider;
    }

    @Override
    @SuppressWarnings("unchecked")
    public PlatformView create(Context context, int viewId, Object args) {
        final AMapOptionsBuilder builder = new AMapOptionsBuilder();
        try {
            Map<String, Object> params = args instanceof Map
                    ? (Map<String, Object>) args
                    : Collections.<String, Object>emptyMap();
            if (params.containsKey("debugMode")) {
                LogUtil.isDebugMode = ConvertUtil.toBoolean(params.get("debugMode"));
            }
            ConvertUtil.initialize(context);
            ConvertUtil.density = context.getResources().getDisplayMetrics().density;

            LogUtil.i(CLASS_NAME, "create params==>" + params);
            if (params.containsKey("privacyStatement")) {
                ConvertUtil.setPrivacyStatement(context, params.get("privacyStatement"));
            }

            Object options = params.get("options");
            if (null != options) {
                ConvertUtil.interpretAMapOptions(options, builder);
            }

            if (params.containsKey("initialCameraPosition")) {
                CameraPosition cameraPosition = ConvertUtil.toCameraPosition(params.get("initialCameraPosition"));
                builder.setCamera(cameraPosition);
            }

            if (params.containsKey("markersToAdd")) {
                builder.setInitialMarkers(params.get("markersToAdd"));
            }
            if (params.containsKey("polylinesToAdd")) {
                builder.setInitialPolylines(params.get("polylinesToAdd"));
            }

            if (params.containsKey("polygonsToAdd")) {
                builder.setInitialPolygons(params.get("polygonsToAdd"));
            }


            if (params.containsKey("apiKey")) {
                ConvertUtil.checkApiKey(params.get("apiKey"));
            }
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "<create>", e);
            throw e;
        }
        return builder.build(viewId, context, binaryMessenger, lifecycleProvider);
    }
}
