/**
 * Marker icon descriptor factory.
 *
 * @author 913721086@qq.com
 * @date 2026/7/13
 */
package com.amap.flutter.map.overlays.marker;

import android.content.Context;

import com.amap.api.maps.model.BitmapDescriptor;
import com.amap.api.maps.model.BitmapDescriptorFactory;

import java.util.Map;

public final class MarkerIconDescriptorFactory {
    public MarkerIconDescriptorFactory() {
    }

    public static final class MarkerIcon {
        public final BitmapDescriptor descriptor;

        MarkerIcon(BitmapDescriptor descriptor) {
            this.descriptor = descriptor;
        }
    }

    public MarkerIcon create(Context context, Object iconData) {
        Map<String, Object> iconMap = asMap(iconData);
        MarkerIconJsonRenderer.RenderedIcon rendered = MarkerIconJsonRenderer.renderIcon(context, iconMap);
        return new MarkerIcon(BitmapDescriptorFactory.fromView(rendered.view));
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> asMap(Object value) {
        if (value instanceof Map) {
            return (Map<String, Object>) value;
        }
        return java.util.Collections.emptyMap();
    }
}
