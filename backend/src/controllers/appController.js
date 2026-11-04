let cachedRelease = null;
let lastFetchTime = 0;
const CACHE_DURATION_MS = 2 * 60 * 1000; // 2 minutes

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
          const tagName = readyRelease.tag_name || 'v1.0.16';
          const version = tagName.replace(/^v/, '');
          const apkAsset = readyRelease.assets.find(a => a.name && a.name.endsWith('.apk') && a.state === 'uploaded');

          cachedRelease = {
            latestVersion: version,
            tagName: tagName,
            releaseName: readyRelease.name || `Release ${tagName}`,
            releaseNotes: readyRelease.body || 'New update available with performance improvements and bug fixes.',
            downloadUrl: apkAsset.browser_download_url,
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
        ...cachedRelease
      });
    }

    // Fallback if GitHub rate-limited and no cache yet
    const fallback = {
      latestVersion: '1.0.15',
      tagName: 'v1.0.15',
      releaseName: 'Suprime Solutions v1.0.15',
      releaseNotes: 'Fixed customer outstanding due balance display and live reconciliation.',
      downloadUrl: 'https://github.com/suprimesolution2000-art/Suprime-Solutions/releases/download/v1.0.15/Suprime_Solutions_v1.0.15.apk',
      apkSize: 38188402,
      publishedAt: new Date().toISOString()
    };
    return res.json({
      success: true,
      ...fallback
    });
  } catch (err) {
    console.error('Error fetching latest release:', err.message);
    if (cachedRelease) {
      return res.json({
        success: true,
        ...cachedRelease
      });
    }
    return res.json({
      success: true,
      latestVersion: '1.0.15',
      tagName: 'v1.0.15',
      releaseName: 'Suprime Solutions v1.0.15',
      releaseNotes: 'Fixed customer outstanding due balance display and live reconciliation.',
      downloadUrl: 'https://github.com/suprimesolution2000-art/Suprime-Solutions/releases/download/v1.0.15/Suprime_Solutions_v1.0.15.apk',
      apkSize: 38188402,
      publishedAt: new Date().toISOString()
    });
  }
};

module.exports = {
  getLatestRelease
};
