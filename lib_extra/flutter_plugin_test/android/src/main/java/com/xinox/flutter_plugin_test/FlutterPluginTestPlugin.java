package com.xinox.flutter_plugin_test;

import androidx.annotation.NonNull;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

public class FlutterPluginTestPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    binding
            .getPlatformViewRegistry()
            .registerViewFactory("NativeExampleView", new NativeViewFactory());
  }

  @Override
  public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {}
}

