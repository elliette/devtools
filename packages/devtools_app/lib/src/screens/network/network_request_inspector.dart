// Copyright 2019 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file or at https://developers.google.com/open-source/licenses/bsd.

import 'package:devtools_app_shared/ui.dart';
import 'package:flutter/material.dart';

import '../../shared/analytics/constants.dart' as gac;
import '../../shared/globals.dart';
import '../../shared/http/http_request_data.dart';
import '../../shared/ui/tab.dart';
import '../../shared/ui/utils.dart';
import 'network_controller.dart';
import 'network_model.dart';
import 'network_request_inspector_views.dart';
import 'network_screen.dart';

/// A [Widget] which displays information about a network request.
class NetworkRequestInspector extends StatelessWidget {
  const NetworkRequestInspector({super.key});

  static const _overviewTabTitle = 'Overview';
  static const _headersTabTitle = 'Headers';
  static const _requestTabTitle = 'Request';
  static const _responseTabTitle = 'Response';
  static const _cookiesTabTitle = 'Cookies';

  NetworkController get controller =>
      screenControllers.lookup<NetworkController>();

  DevToolsTab _buildTab({required String tabName, Widget? trailing}) {
    return DevToolsTab.create(
      tabName: tabName,
      gaPrefix: 'requestInspectorTab',
      trailing: trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NetworkRequest?>(
      valueListenable: controller.selectedRequest,
      builder: (context, data, _) {
        return data == null
            ? RoundedOutlinedBorder(
                child: Center(
                  child: Text(
                    'No request selected',
                    style: Theme.of(context).regularTextStyle,
                  ),
                ),
              )
            : ListenableBuilder(
                listenable: data,
                builder: (context, _) {
                  return AnalyticsTabbedView(
                    analyticsSessionIdentifier: data.id,
                    tabs: _generateTabs(data),
                    gaScreen: gac.network,
                  );
                },
              );
      },
    );
  }

  List<({DevToolsTab tab, Widget tabView})> _generateTabs(NetworkRequest data) {
    final tabs = [
      (
        tab: _buildTab(tabName: _overviewTabTitle),
        tabView: highlightableWidget(
          child: NetworkRequestOverviewView(
            data,
            key: NetworkScreen.networkRequestOverviewKey,
          ),
        ),
      ),
      if (data is DartIOHttpRequestData) ...[
        (
          tab: _buildTab(tabName: _headersTabTitle),
          tabView: highlightableWidget(
            child: HttpRequestHeadersView(
              data,
              key: NetworkScreen.networkRequestHeadersKey,
            ),
          ),
        ),
        if (data.requestBody != null)
          (
            tab: _buildTab(
              tabName: _requestTabTitle,
              trailing: HttpViewTrailingCopyButton(
                data,
                (data) => data.requestBody,
              ),
            ),
            tabView: highlightableWidget(
              child: HttpRequestView(
                data,
                key: NetworkScreen.networkRequestBodyKey,
              ),
            ),
          ),
        if (data.responseBody != null)
          (
            tab: _buildTab(
              tabName: _responseTabTitle,
              trailing: Row(
                children: [
                  HttpResponseTrailingDropDown(
                    data,
                    currentResponseViewType: controller.currentResponseViewType,
                    onChanged: (value) =>
                        controller.setResponseViewType = value,
                  ),
                  HttpViewTrailingCopyButton(data, (data) => data.responseBody),
                ],
              ),
            ),
            tabView: highlightableWidget(
              child: HttpResponseView(
                data,
                currentResponseViewType: controller.currentResponseViewType,
                key: NetworkScreen.networkResponseBodyKey,
              ),
            ),
          ),
        if (data.hasCookies)
          (
            tab: _buildTab(tabName: _cookiesTabTitle),
            tabView: highlightableWidget(
              child: HttpRequestCookiesView(
                data,
                key: NetworkScreen.networkRequestCookiesKey,
              ),
            ),
          ),
      ],
    ];
    return tabs
        .map(
          (t) => (
            tab: t.tab,
            tabView: OutlineDecoration.onlyTop(child: t.tabView),
          ),
        )
        .toList();
  }
}
