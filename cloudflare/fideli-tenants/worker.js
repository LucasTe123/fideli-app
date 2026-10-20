const FIDELI_ORIGIN =
  "https://fideli-club-lucas.lucrecio23.chatgpt.site";

export default {
  async fetch(request) {
    const incomingUrl = new URL(request.url);
    const originUrl = new URL(
      incomingUrl.pathname + incomingUrl.search,
      FIDELI_ORIGIN,
    );
    const headers = new Headers(request.headers);
    headers.delete("host");
    headers.set("x-forwarded-host", incomingUrl.hostname);

    const init = {
      method: request.method,
      headers,
      redirect: "manual",
    };

    if (request.method !== "GET" && request.method !== "HEAD") {
      init.body = request.body;
    }

    const originResponse = await fetch(originUrl, init);
    const responseHeaders = new Headers(originResponse.headers);

    if (
      incomingUrl.hostname.endsWith(".fideli.site") &&
      incomingUrl.hostname !== "www.fideli.site"
    ) {
      responseHeaders.set(
        "X-Robots-Tag",
        "noindex, nofollow, noarchive",
      );
    }

    return new Response(originResponse.body, {
      status: originResponse.status,
      statusText: originResponse.statusText,
      headers: responseHeaders,
    });
  },
};
