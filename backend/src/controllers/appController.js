let cachedRelease = null;
let lastFetchTime = 0;
const CACHE_DURATION_MS = 5 * 60 * 1000; // 5 minutes

/**
 * Fetch latest release metadata from GitHub or cache/fallback
 */
const getLatestRelease = async (req, res) => {
  try {
    const now = Date.now();
    if (cachedRelease && (now - lastFetchTime < CACHE_DURATION_MS)) {
      return res.json({
        success: true,
        ...cachedRelease
      });
    }

    // Try fetching from GitHub releases API
    const headers = {
      'User-Agent': 'Suprime-Solutions-Backend',
      'Accept': 'application/vnd.github.v3+json'
    };
    if (process.env.GITHUB_TOKEN) {
      headers['Authorization'] = `token ${process.env.GITHUB_TOKEN}`;
    }

    const response = await fetch('https://api.github.com/repos/suprimesolution2000-art/Suprime-Solutions/releases/latest', {
      headers
    });

    if (response.ok) {
      const data = await response.json();
      const tagName = data.tag_name || 'v1.0.15';
      const version = tagName.replace(/^v/, '');
      const apkAsset = (data.assets || []).find(a => a.name && a.name.endsWith('.apk'));

      if (apkAsset) {
        cachedRelease = {
          latestVersion: version,
          tagName: tagName,
          releaseName: data.name || `Release ${tagName}`,
          releaseNotes: data.body || 'New update available with performance improvements and bug fixes.',
          downloadUrl: apkAsset.browser_download_url,
          apkSize: apkAsset.size,
          publishedAt: data.published_at || new Date().toISOString()
        };
        lastFetchTime = now;

        return res.json({
          success: true,
          ...cachedRelease
        });
      }
    }

    // Fallback if GitHub rate-limited or unreachable
    const fallback = {
      latestVersion: '1.0.15',
      tagName: 'v1.0.15',
      releaseName: 'Suprime Solutions v1.0.15',
      releaseNotes: 'Fixed customer outstanding due balance display and live reconciliation.',
      downloadUrl: 'https://github.com/suprimesolution2000-art/Suprime-Solutions/releases/download/v1.0.15/Suprime_Solutions_v1.0.15.apk',
      apkSize: null,
      publishedAt: new Date().toISOString()
    };
    return res.json({
      success: true,
      ...fallback
    });
  } catch (err) {
    console.error('Error fetching latest release:', err.message);
    return res.json({
      success: true,
      latestVersion: '1.0.15',
      tagName: 'v1.0.15',
      releaseName: 'Suprime Solutions v1.0.15',
      releaseNotes: 'Fixed customer outstanding due balance display and live reconciliation.',
      downloadUrl: 'https://github.com/suprimesolution2000-art/Suprime-Solutions/releases/download/v1.0.15/Suprime_Solutions_v1.0.15.apk',
      apkSize: null,
      publishedAt: new Date().toISOString()
    });
  }
};

module.exports = {
  getLatestRelease
};
