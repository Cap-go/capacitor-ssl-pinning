# @capgo/capacitor-ssl-pinning
<a href="https://capgo.app/"><img src="https://capgo.app/readme-banner.svg?repo=Cap-go/capacitor-ssl-pinning" alt="Capgo - Instant updates for Capacitor" /></a>

<div align="center">
  <h2><a href="https://capgo.app/?ref=plugin_ssl_pinning"> ➡️ Get Instant updates for your App with Capgo</a></h2>
  <h2><a href="https://capgo.app/consulting/?ref=plugin_ssl_pinning"> Missing a feature? We’ll build the plugin for you 💪</a></h2>
</div>

Capgo SSL Pinning brings certificate pinning to Capacitor 8 apps by integrating with `CapacitorHttp` on Android and iOS.

The implementation follows the Ionic SSL pinning install flow and uses the same `plugins.SSLPinning` configuration shape documented at [ionic.io](https://ionic.io/docs/ssl-pinning/install).

## Documentation

The most complete doc is available here: https://capgo.app/docs/plugins/ssl-pinning/

## Compatibility

| Plugin version | Capacitor compatibility | Maintained |
| -------------- | ----------------------- | ---------- |
| v8.\*.\*       | v8.\*.\*                | ✅          |

## Install

You can use our AI-Assisted Setup to install the plugin. Add the Capgo skills to your AI tool using the following command:

```bash
npx skills add https://github.com/cap-go/capacitor-skills --skill capacitor-plugins
```

Then use the following prompt:

```text
Use the `capacitor-plugins` skill from `cap-go/capacitor-skills` to install the `@capgo/capacitor-ssl-pinning` plugin in my project.
```

If you prefer Manual Setup, install the plugin by running the following commands and follow the platform-specific instructions below:

```bash
bun add @capgo/capacitor-ssl-pinning
bunx cap sync
```

## Configure

Enable Capacitor HTTP interception and declare the certificate files relative to your app root:

```ts
import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  plugins: {
    CapacitorHttp: {
      enabled: true,
    },
    SSLPinning: {
      certs: ['sslCerts/production/primary.cer', 'sslCerts/production/backup.der'],
      excludedDomains: ['https://analytics.google.com'],
    },
  },
};

export default config;
```

During `bunx cap sync`, the plugin copies the configured certificates into `webDir/certs`, which lets both native implementations load them from the bundled app assets. Both `.cer` and `.der` are supported; PEM `.cer` files are converted to DER automatically for iOS.

## Usage

Make HTTPS calls with `CapacitorHttp`:

```ts
import { CapacitorHttp } from '@capacitor/core';

const response = await CapacitorHttp.get({
  url: 'https://api.example.com/health',
});
```

If the server certificate does not match one of the pinned certificates, the native request fails.

## Behavior

- Android injects a pinned `SSLSocketFactory` into Capacitor HTTP requests unless the URL matches `excludedDomains`.
- iOS swaps the default Capacitor HTTP handler with a pinned `URLSession` delegate and also answers WebView authentication challenges through the Capacitor plugin hook.
- Web exposes inspection helpers only; browsers do not support this native pinning behavior.

## API

<docgen-index>

* [`getConfiguration()`](#getconfiguration)
* [`getPluginVersion()`](#getpluginversion)
* [Interfaces](#interfaces)

</docgen-index>

<docgen-api>
<!--Update the source file JSDoc comments and rerun docgen to update the docs below-->

Capacitor API for inspecting SSL pinning configuration.

Native enforcement is applied automatically to `CapacitorHttp` requests when:
1. `plugins.CapacitorHttp.enabled` is `true`
2. `plugins.SSLPinning.certs` contains at least one certificate

### getConfiguration()

```typescript
getConfiguration() => Promise<SSLPinningConfigurationState>
```

Returns the active native configuration visible to the plugin.

**Returns:** <code>Promise&lt;<a href="#sslpinningconfigurationstate">SSLPinningConfigurationState</a>&gt;</code>

--------------------


### getPluginVersion()

```typescript
getPluginVersion() => Promise<PluginVersionResult>
```

Returns the native implementation version marker.

**Returns:** <code>Promise&lt;<a href="#pluginversionresult">PluginVersionResult</a>&gt;</code>

--------------------


### Interfaces


#### SSLPinningConfigurationState

Static SSL pinning configuration currently visible to the plugin.

| Prop                  | Type                  | Description                                                           |
| --------------------- | --------------------- | --------------------------------------------------------------------- |
| **`configured`**      | <code>boolean</code>  | Whether at least one certificate is configured for native pinning.    |
| **`certs`**           | <code>string[]</code> | Certificate paths from `capacitor.config.*` relative to the app root. |
| **`excludedDomains`** | <code>string[]</code> | Fully-qualified URLs that should bypass SSL pinning.                  |


#### PluginVersionResult

Plugin version payload.

| Prop          | Type                | Description                                                 |
| ------------- | ------------------- | ----------------------------------------------------------- |
| **`version`** | <code>string</code> | Version identifier returned by the platform implementation. |

</docgen-api>
