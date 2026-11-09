let cachedRelease = null;
let lastFetchTime = 0;
const CACHE_DURATION_MS = 2 * 60 * 1000; // 2 minutes

/**
 * Fetch latest release metadata from GitHub or cache/fallback
 */
const getLatestRelease = async (req, res) => {
  try {
    const now = Date.now();
    const hostUrl = `${req.protocol}://${req.get('host')}`;
    const directBackendDownloadUrl = `${hostUrl}/api/app/download`;

    if (cachedRelease && (now - lastFetchTime < CACHE_DURATION_MS)) {
      return res.json({
        success: true,
        ...cachedRelease,
        downloadUrl: directBackendDownloadUrl
      });
    }

    const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
    const headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/vnd.github.v3+json',
      ...(token ? { 'Authorization': `token ${token}` } : {})
    };

    const response = await fetch('https://api.github.com/repos/suprimesolution2000-art/Suprime-Solutions/releases?per_page=5', {
      headers
    });

    if (response.ok) {
      const releases = await response.json();
      if (Array.isArray(releases)) {
        // Find newest release that actually has an uploaded .apk file
        const readyRelease = releases.find(r => 
          !r.draft && 
          r.assets && 
          r.assets.some(a => a.name && a.name.endsWith('.apk') && a.state === 'uploaded')
        );

        if (readyRelease) {
          const tagName = readyRelease.tag_name || 'v1.0.29';
          const version = tagName.replace(/^v/, '');
          const apkAsset = readyRelease.assets.find(a => a.name && a.name.endsWith('.apk') && a.state === 'uploaded');

          cachedRelease = {
            latestVersion: version,
            tagName: tagName,
            releaseName: readyRelease.name || `Release ${tagName}`,
            releaseNotes: readyRelease.body || 'New update available with performance improvements and bug fixes.',
            downloadUrl: directBackendDownloadUrl,
            browserDownloadUrl: apkAsset.browser_download_url,
            apkSize: apkAsset.size,
            publishedAt: readyRelease.published_at || new Date().toISOString()
          };
          lastFetchTime = now;

          return res.json({
            success: true,
            ...cachedRelease
          });
        }
      }
    }

    // If cache exists from prior successful check, use it
    if (cachedRelease) {
      return res.json({
        success: true,
        ...cachedRelease,
        downloadUrl: directBackendDownloadUrl
      });
    }

    // Fallback if GitHub rate-limited and no cache yet
    const fallback = {
      latestVersion: '1.0.29',
      tagName: 'v1.0.29',
      releaseName: 'Suprime Solutions v1.0.29',
      releaseNotes: 'Fixed item selection keyboard auto-dismiss, prevented Customer Name viewport jump, and added high-speed resilient APK downloads.',
      downloadUrl: directBackendDownloadUrl,
      browserDownloadUrl: 'https://github.com/suprimesolution2000-art/Suprime-Solutions/releases/download/v1.0.29/Suprime_Solutions_v1.0.29.apk',
      apkSize: 40562004,
      publishedAt: new Date().toISOString()
    };
    return res.json({
      success: true,
      ...fallback
    });
  } catch (err) {
    console.error('Error fetching latest release:', err.message);
    const hostUrl = `${req.protocol}://${req.get('host')}`;
    const directBackendDownloadUrl = `${hostUrl}/api/app/download`;

    if (cachedRelease) {
      return res.json({
        success: true,
        ...cachedRelease,
        downloadUrl: directBackendDownloadUrl
      });
    }
    return res.json({
      success: true,
      latestVersion: '1.0.29',
      tagName: 'v1.0.29',
      releaseName: 'Suprime Solutions v1.0.29',
      releaseNotes: 'Fixed item selection keyboard auto-dismiss, prevented Customer Name viewport jump, and added high-speed resilient APK downloads.',
      downloadUrl: directBackendDownloadUrl,
      browserDownloadUrl: 'https://github.com/suprimesolution2000-art/Suprime-Solutions/releases/download/v1.0.29/Suprime_Solutions_v1.0.29.apk',
      apkSize: 40562004,
      publishedAt: new Date().toISOString()
    });
  }
};

/**
 * High-speed direct APK download endpoint
 * Bypasses GitHub releases/download edge timeouts (HTTP 504) by redirecting directly to Azure CDN storage
 */
const downloadLatestApk = async (req, res) => {
  try {
    const token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN;
    const headers = {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept': 'application/vnd.github.v3+json',
      ...(token ? { 'Authorization': `token ${token}` } : {})
    };

    const response = await fetch('https://api.github.com/repos/suprimesolution2000-art/Suprime-Solutions/releases?per_page=5', {
      headers
    });

    if (response.ok) {
      const releases = await response.json();
      const readyRelease = releases.find(r => 
        !r.draft && 
        r.assets && 
        r.assets.some(a => a.name && a.name.endsWith('.apk') && a.state === 'uploaded')
      );

      if (readyRelease) {
        const apkAsset = readyRelease.assets.find(a => a.name && a.name.endsWith('.apk') && a.state === 'uploaded');
        if (apkAsset && apkAsset.browser_download_url) {
          // Resolve direct Azure CDN redirect from GitHub with browser User-Agent
          const directRes = await fetch(apkAsset.browser_download_url, {
            redirect: 'manual',
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
            }
          });

          const location = directRes.headers.get('location');
          if (location) {
            return res.redirect(302, location);
          }
        }
      }
    }

    return res.redirect(302, 'https://github.com/suprimesolution2000-art/Suprime-Solutions/releases/download/v1.0.28/Suprime_Solutions_v1.0.28.apk');
  } catch (err) {
    console.error('Error redirecting APK download:', err.message);
    return res.redirect(302, 'https://github.com/suprimesolution2000-art/Suprime-Solutions/releases/download/v1.0.28/Suprime_Solutions_v1.0.28.apk');
  }
};

module.exports = {
  getLatestRelease,
  downloadLatestApk
};
