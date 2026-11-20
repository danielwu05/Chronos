// Chronos - X/Twitter +18 signals (MV3 world: MAIN, x.com/twitter.com only).
// Reads X's own API responses (GraphQL) and reports tweets marked possibly_sensitive
// and accounts flagged as sensitive, so the content script can hide/block them even
// when the account's "show sensitive content" setting removes the warnings.
(function () {
  if (window.__chronosXSensitiveHook) return;
  window.__chronosXSensitiveHook = true;

  function collect(node, out, depth) {
    if (!node || typeof node !== "object" || depth > 80) return;
    if (Array.isArray(node)) {
      for (const item of node) collect(item, out, depth + 1);
      return;
    }
    // Communities: {"__typename":"Community","rest_id":..,"is_nsfw":true}
    if (node.rest_id && node.is_nsfw === true && !node.legacy) {
      out.communities.add(String(node.rest_id));
    }
    const leg = node.legacy;
    // Tweet posted in a community: remember the link (the community may be flagged in
    // another response).
    const comm = node.community_results && node.community_results.result;
    if (node.rest_id && leg && comm && comm.rest_id) {
      out.tweetCommunities.push([String(node.rest_id), String(comm.rest_id)]);
      if (comm.is_nsfw === true) {
        out.communities.add(String(comm.rest_id));
        out.tweets.add(String(node.rest_id));
      }
    }
    if (node.rest_id && leg && typeof leg === "object") {
      const sensitiveUser =
        leg.possibly_sensitive === true ||
        node.profile_interstitial_type === "sensitive" ||
        leg.profile_interstitial_type === "sensitive";
      if (leg.screen_name) {
        if (sensitiveUser) out.users.add(String(leg.screen_name).toLowerCase());
      } else if (leg.possibly_sensitive === true) {
        out.tweets.add(String(node.rest_id));
      }
    }
    for (const key in node) {
      if (key !== "legacy") collect(node[key], out, depth + 1);
    }
    if (leg && typeof leg === "object") collect(leg, out, depth + 1);
  }

  function report(data) {
    try {
      const out = { tweets: new Set(), users: new Set(), communities: new Set(), tweetCommunities: [] };
      collect(data, out, 0);
      if (!out.tweets.size && !out.users.size && !out.communities.size && !out.tweetCommunities.length) return;
      window.dispatchEvent(
        new CustomEvent("chronos-x-sensitive", {
          detail: JSON.stringify({
            tweets: Array.from(out.tweets),
            users: Array.from(out.users),
            communities: Array.from(out.communities),
            tweetCommunities: out.tweetCommunities.slice(0, 500),
          }),
        })
      );
    } catch (_) {}
  }

  function isApiUrl(url) {
    return typeof url === "string" && (url.includes("/graphql/") || url.includes("/i/api/"));
  }

  const origFetch = window.fetch;
  if (typeof origFetch === "function") {
    window.fetch = function () {
      const args = arguments;
      const p = origFetch.apply(this, args);
      try {
        const req = args[0];
        const url = typeof req === "string" ? req : req && req.url;
        if (isApiUrl(url)) {
          p.then((res) => {
            try {
              res
                .clone()
                .json()
                .then(report)
                .catch(() => {});
            } catch (_) {}
          }).catch(() => {});
        }
      } catch (_) {}
      return p;
    };
  }

  const origOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    try {
      if (isApiUrl(String(url))) {
        this.addEventListener("load", function () {
          try {
            if (this.responseType === "json") report(this.response);
            else if (this.responseType === "" || this.responseType === "text") report(JSON.parse(this.responseText));
          } catch (_) {}
        });
      }
    } catch (_) {}
    return origOpen.apply(this, arguments);
  };
})();
