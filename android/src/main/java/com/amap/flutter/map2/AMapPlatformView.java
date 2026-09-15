package com.amap.flutter.map2;

import android.content.Context;
import android.os.Bundle;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.lifecycle.DefaultLifecycleObserver;
import androidx.lifecycle.Lifecycle;
import androidx.lifecycle.LifecycleOwner;

import com.amap.api.maps.AMap;
import com.amap.api.maps.AMapOptions;
import com.amap.api.maps.TextureMapView;
import com.amap.flutter.map2.core.MapController;
import com.amap.flutter.map2.core.MapsInitializerController;
import com.amap.flutter.map2.overlays.marker.MarkersController;
import com.amap.flutter.map2.overlays.polygon.PolygonsController;
import com.amap.flutter.map2.overlays.polyline.PolylinesController;
import com.amap.flutter.map2.utils.LogUtil;

import java.util.HashMap;
import java.util.Map;
import java.util.Objects;
import java.util.concurrent.atomic.AtomicBoolean;

import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.platform.PlatformView;


/**
 * @author whm
 * @date 2020/10/27 5:49 PM
 * @mail hongming.whm@alibaba-inc.com
 * @since
 */
public class AMapPlatformView
        implements
        DefaultLifecycleObserver,
        ActivityPluginBinding.OnSaveInstanceStateListener,
        MethodChannel.MethodCallHandler,
        PlatformView {
    private static final String CLASS_NAME = "AMapPlatformView";
    private final MethodChannel methodChannel;
    private final Map<String, MyMethodCallHandler> myMethodCallHandlerMap;

    private MapsInitializerController mapsInitializerController;
    private MapController mapController;
    private MarkersController markersController;
    private PolylinesController polylinesController;
    private PolygonsController polygonsController;
    private TextureMapView mapView;
    /**
     * Lifecycle callbacks and PlatformView.dispose() can both try to tear down
     * the same TextureMapView.  The SDK's native delegate is not safe to destroy
     * twice, so this state must be claimed before entering native code.
     */
    private final AtomicBoolean disposed = new AtomicBoolean(false);
    private Lifecycle mapLifecycle;
    private boolean mapCreated;

    AMapPlatformView(int id,
                     Context context,
                     BinaryMessenger binaryMessenger,
                     LifecycleOwner lifecycleProvider,
                     AMapOptions options) {

        methodChannel = new MethodChannel(binaryMessenger, "amap_map2_" + id);
        methodChannel.setMethodCallHandler(this);
        myMethodCallHandlerMap = new HashMap<>(8);

        try {
            mapView = new TextureMapView(context, options);
            AMap amap = mapView.getMap();
            mapsInitializerController = new MapsInitializerController(methodChannel);
            mapController = new MapController(methodChannel, mapView);
            markersController = new MarkersController(methodChannel, amap);
            polylinesController = new PolylinesController(methodChannel, amap);
            polygonsController = new PolygonsController(methodChannel, amap);
            initMyMethodCallHandlerMap();
            Lifecycle lifecycle = lifecycleProvider == null ? null : lifecycleProvider.getLifecycle();
            if (lifecycle != null) {
                mapLifecycle = lifecycle;
                lifecycle.addObserver(this);
            } else {
                throw new IllegalStateException("AMap lifecycle owner is unavailable");
            }
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "<init>", e);
            try {
                destroyMapViewIfNecessary();
            } catch (Throwable cleanupError) {
                LogUtil.e(CLASS_NAME, "<init> cleanup", cleanupError);
            }
            if (e instanceof RuntimeException) {
                throw (RuntimeException) e;
            }
            if (e instanceof Error) {
                throw (Error) e;
            }
            throw new IllegalStateException("AMap platform view initialization failed", e);
        }
    }

    private void initMyMethodCallHandlerMap() {
        String[] methodIdArray = mapController.getRegisterMethodIdArray();
        if (null != methodIdArray) {
            for (String methodId : methodIdArray) {
                myMethodCallHandlerMap.put(methodId, mapController);
            }
        }

        methodIdArray = mapsInitializerController.getRegisterMethodIdArray();
        if (null != methodIdArray) {
            for (String methodId : methodIdArray) {
                myMethodCallHandlerMap.put(methodId, mapsInitializerController);
            }
        }

        methodIdArray = markersController.getRegisterMethodIdArray();
        if (null != methodIdArray) {
            for (String methodId : methodIdArray) {
                myMethodCallHandlerMap.put(methodId, markersController);
            }
        }

        methodIdArray = polylinesController.getRegisterMethodIdArray();
        if (null != methodIdArray) {
            for (String methodId : methodIdArray) {
                myMethodCallHandlerMap.put(methodId, polylinesController);
            }
        }

        methodIdArray = polygonsController.getRegisterMethodIdArray();
        if (null != methodIdArray) {
            for (String methodId : methodIdArray) {
                myMethodCallHandlerMap.put(methodId, polygonsController);
            }
        }
    }


    public MapController getMapController() {
        return mapController;
    }

    public MarkersController getMarkersController() {
        return markersController;
    }

    public PolylinesController getPolylinesController() {
        return polylinesController;
    }

    public PolygonsController getPolygonsController() {
        return polygonsController;
    }


    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        LogUtil.i(CLASS_NAME, "onMethodCall==>" + call.method + ", arguments==> " + call.arguments);
        if (disposed.get()) {
            result.error("map_disposed", "地图视图已销毁。", null);
            return;
        }
        String methodId = call.method;
        if (myMethodCallHandlerMap.containsKey(methodId)) {
            Objects.requireNonNull(myMethodCallHandlerMap.get(methodId)).doMethodCall(call, result);
        } else {
            LogUtil.w(CLASS_NAME, "onMethodCall, the methodId: " + call.method + ", not implemented");
            result.notImplemented();
        }
    }


    @Override
    public void onCreate(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onCreate==>");
        try {
            if (disposed.get() || mapCreated) {
                return;
            }
            if (null != mapView) {
                mapView.onCreate(null);
                mapCreated = true;
            }
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "onCreate", e);
        }
    }

    @Override
    public void onStart(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onStart==>");
    }

    @Override
    public void onResume(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onResume==>");
        try {
            if (disposed.get()) {
                return;
            }
            if (null != mapView) {
                mapView.onResume();
            }
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "onResume", e);
        }
    }

    @Override
    public void onPause(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onPause==>");
        try {
            if (disposed.get()) {
                return;
            }
            if (mapView != null) {
                mapView.onPause();
            }
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "onPause", e);
        }
    }

    @Override
    public void onStop(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onStop==>");
    }

    @Override
    public void onDestroy(@NonNull LifecycleOwner owner) {
        LogUtil.i(CLASS_NAME, "onDestroy==>");
        try {
            destroyMapViewIfNecessary();
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "onDestroy", e);
        }
    }

    @Override
    public void onSaveInstanceState(@NonNull Bundle bundle) {
        LogUtil.i(CLASS_NAME, "onSaveInstanceState==>");
        try {
            if (disposed.get()) {
                return;
            }
            if (mapView != null) {
                mapView.onSaveInstanceState(bundle);
            }
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "onSaveInstanceState", e);
        }
    }

    @Override
    public void onRestoreInstanceState(@Nullable Bundle bundle) {
        // TextureMapView is created exactly once in onCreate(). Calling
        // onCreate() from restore would create the native map delegate twice.
        LogUtil.i(CLASS_NAME, "onRestoreInstanceState ignored; state is restored by onCreate");
    }


    @Override
    public View getView() {
        LogUtil.i(CLASS_NAME, "getView==>");
        return mapView;
    }

    @Override
    public void dispose() {
        LogUtil.i(CLASS_NAME, "dispose==>");
        try {
            destroyMapViewIfNecessary();
        } catch (Throwable e) {
            LogUtil.e(CLASS_NAME, "dispose", e);
        }
    }

    private void destroyMapViewIfNecessary() {
        if (!disposed.compareAndSet(false, true)) {
            return;
        }
        methodChannel.setMethodCallHandler(null);

        if (mapLifecycle != null) {
            mapLifecycle.removeObserver(this);
            mapLifecycle = null;
        }

        // Detach plugin listeners before destroying the native map. Each
        // controller is allowed to finish its own pending callbacks safely.
        try {
            if (mapController != null) {
                mapController.dispose();
            }
        } catch (Throwable error) {
            LogUtil.e(CLASS_NAME, "dispose map controller", error);
        }
        try {
            if (markersController != null) {
                markersController.dispose();
            }
        } catch (Throwable error) {
            LogUtil.e(CLASS_NAME, "dispose marker controller", error);
        }
        try {
            if (polylinesController != null) {
                polylinesController.dispose();
            }
        } catch (Throwable error) {
            LogUtil.e(CLASS_NAME, "dispose polyline controller", error);
        }
        try {
            if (polygonsController != null) {
                polygonsController.dispose();
            }
        } catch (Throwable error) {
            LogUtil.e(CLASS_NAME, "dispose polygon controller", error);
        }

        TextureMapView view = mapView;
        mapView = null;
        if (view != null) {
            try {
                view.onDestroy();
            } catch (Throwable error) {
                LogUtil.e(CLASS_NAME, "destroy TextureMapView", error);
            }
        }
    }


}
