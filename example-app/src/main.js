import { CapacitorUpdater } from '@capgo/capacitor-updater';
import { Capacitor } from '@capacitor/core';
import './style.css';
import { SSLPinning } from '@capgo/capacitor-ssl-pinning';

const output = document.getElementById('plugin-output');
const configBadge = document.getElementById('config-badge');
const readConfigButtons = document.querySelectorAll('[data-action="read-config"]');
const versionButton = document.getElementById('get-version');

const setOutput = (value) => {
  output.textContent = typeof value === 'string' ? value : JSON.stringify(value, null, 2);
};

const setConfigured = (configured) => {
  configBadge.textContent = configured ? 'Configured' : 'Missing certs';
  configBadge.dataset.enabled = String(configured);
};

const refreshConfiguration = async () => {
  try {
    const result = await SSLPinning.getConfiguration();
    setConfigured(result.configured);
    setOutput(result);
  } catch (error) {
    setOutput(`Error: ${error?.message ?? error}`);
  }
};

readConfigButtons.forEach((button) => {
  button.addEventListener('click', refreshConfiguration);
});

versionButton.addEventListener('click', async () => {
  try {
    const result = await SSLPinning.getPluginVersion();
    setOutput(result);
  } catch (error) {
    setOutput(`Error: ${error?.message ?? error}`);
  }
});

refreshConfiguration();

if (Capacitor.isNativePlatform()) {
  CapacitorUpdater.notifyAppReady().catch((error) => {
    console.error('Capgo notifyAppReady failed', error);
  });
}
