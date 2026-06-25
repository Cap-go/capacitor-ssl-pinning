/**
 * Plugin version payload.
 */
export interface PluginVersionResult {
  /**
   * Version identifier returned by the platform implementation.
   */
  version: string;
}

/**
 * Static SSL pinning configuration currently visible to the plugin.
 */
export interface SSLPinningConfigurationState {
  /**
   * Whether at least one certificate is configured for native pinning.
   */
  configured: boolean;

  /**
   * Certificate paths from `capacitor.config.*` relative to the app root.
   */
  certs: string[];

  /**
   * Fully-qualified URLs that should bypass SSL pinning.
   */
  excludedDomains: string[];
}

/**
 * Plugin configuration added under `plugins.SSLPinning` in `capacitor.config.*`.
 */
export interface SSLPinningPluginConfig {
  /**
   * Certificate files relative to the application root.
   *
   * During `bunx cap sync`, this plugin copies them into `webDir/certs` so native runtimes can load them from
   * the bundled web assets.
   *
   * Both `.cer` and `.der` filenames are supported. iOS requires DER-encoded X.509 certificates; when a
   * certificate file is provided in PEM form (for example a `.cer` containing `-----BEGIN CERTIFICATE-----`),
   * the sync hook converts it to DER while keeping the same filename.
   */
  certs?: string[];

  /**
   * Fully-qualified URLs that should bypass pinning.
   *
   * Match is done by origin, and by path-prefix when the configured URL contains a path.
   */
  excludedDomains?: string[];
}

/**
 * Capacitor API for inspecting SSL pinning configuration.
 *
 * Native enforcement is applied automatically to `CapacitorHttp` requests when:
 * 1. `plugins.CapacitorHttp.enabled` is `true`
 * 2. `plugins.SSLPinning.certs` contains at least one certificate
 */
export interface SSLPinningPlugin {
  /**
   * Returns the active native configuration visible to the plugin.
   */
  getConfiguration(): Promise<SSLPinningConfigurationState>;

  /**
   * Returns the native implementation version marker.
   */
  getPluginVersion(): Promise<PluginVersionResult>;
}
