// Serve the existing public Pages site without redirecting either public host.
const hostname = 'bubble-tax.workromancer.ai';
const origin = 'https://bubble-tax.github.io';
export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (url.hostname !== hostname) return new Response('Not found', {status:404});
    if (!['GET', 'HEAD'].includes(request.method)) return new Response('Method not allowed', {status:405, headers:{Allow:'GET, HEAD'}});
    if (url.protocol !== 'https:') { url.protocol = 'https:'; return Response.redirect(url.href, 301); }
    const target = new URL(origin);
    target.pathname = url.pathname;
    target.search = url.search;
    const headers = new Headers();
    for (const name of ['accept', 'if-none-match', 'if-modified-since', 'range']) {
      if (request.headers.has(name)) headers.set(name, request.headers.get(name));
    }
    try {
      const upstream = await fetch(target, {method:request.method, headers, redirect:'manual', cf:{cacheTtl:0}});
      const response = new Response(upstream.body, upstream);
      const location = response.headers.get('location');
      if (location) {
        const next = new URL(location, origin);
        if (next.origin === origin) { next.hostname = hostname; response.headers.set('location', next.href); }
      }
      response.headers.delete('set-cookie');
      response.headers.set('Cache-Control', 'public, max-age=60, must-revalidate');
      response.headers.set('X-Content-Type-Options', 'nosniff');
      return response;
    } catch {
      return new Response('Temporarily unavailable. Please try again.', {status:503, headers:{'Cache-Control':'no-store'}});
    }
  },
};
