# How to use active storage

Active storage interfaces with AWS S3. The keys are in the credentials file. Active Storage handles everything transparently and all you have to do is read the docs and follow some guidelines.

This guide was written back when we were paying excessive amounts to serve the same assets to bots.

## Active Storage resolution mode

We use active storage in proxy mode; server downloads from AWS and then forwards the file to the user. That way the CDN gets to cache that file for us and save us from excessive AWS S3 bandwidth costs. It does mean that our server is still under load from downloading and forwarding the images, but only on cache misses.

Redirect mode is still on and accessible. That sends you directly to AWS. Bots somehow manage to find those URLs and keep downloading them, so I put a cloudflare security rule to show a captcha everytime one is accessed. Keep it through proxy mode, let cloudflare handle it.

## Active storage variants

If you're displaying a user-uploaded image as a thumbnail, consider defining a variant with a reduced image size. This is to compress the image and reduce bandwidth costs.

For example, consider the search page or the home page carousel. There's going to be a lot of images downloaded and users are looking at one image only - the rest was downloaded and not even looked at, and we paid in bandwidth costs.

If displaying an image, give the image tag a fixed height with CSS

## Monitoring costs

Cloudflare analytics dashboard is important for detecting abnormal activity spikes. We have a few security rules that end up blocking a lot of bots. These blocks still show up in the activity panel, you will need to filter out responses with 'None' cache responses.

For each AWS S3 buckets you can enable network monitoring metrics to see how much data is being requested. Use this to monitor for any excessive usage and block through cloudflare accordingly. The request metrics are free if they don't exceed a certain threshold.

# HTTP caching

Mandatory reading:
https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Cache-Control

Okay so turns out we haven't been caching anything since the start and that explains the terrifying bills we've been paying.
I'm messed around a bit with the TTL and the cache-control headers, but ended up enabling a Cloudflare "Cache Rule" that serves all `/rails/active_storage` routes through the CDN for 14 days. This is enabled on staging and production. Ideas to think about:

1. If it works out then we could see if it'll work with ActiveStorage proxy mode off.
2. These are static files that don't really change, consider increasing the cache TTL. Right now it's 14 days.
3. Deleted files would still persist in cache, for 14 days right now. Would there be a way for Cloudflare to test new versions of the file?

## Static file caching

Files served from `/public/`, `/assets/`, or `/vite/assets` are static and are handled by either Apache2 on production and staging, or by Thin on development. Rails does not serve those, and thus headers must be set via configuration files in `/etc/apache2/sites-enabled` for actual servers. Caching on development is disabled, because the files change often.

All responses from makerepo include a header that describes the web server used, so that would help determining who sets the headers. However keep in mind Cloudflare does strip them out if enabled.

```
<Location /assets/>
    # Use of ETag is discouraged when Last-Modified is present
    #Header unset ETag
    FileETag None
    # RFC says only cache for 1 year
    ExpiresActive On
    ExpiresDefault "access plus 1 year"
</Location>
```

Setting the header directive breaks apache, no clue what module that comes from.

## Active storage caching

https://bitcrowd.dev/a-caching-journey/

This one is a bit more tricky, since we proxy files through the web server for the CDN to pick it up. AWS has their own metadata for determining headers to serve. These headers are set as metadata on upload, as described in `config/storage.yml`.

Active storage files are served through `https://makerepo.com/rails/active_storage` URL path.

# Other options

- AWS does offer their own cloudfront caching service, but I'm wary of it because of AWS's reputation to present sudden massive bills.
- Cloudflare has their own S3 compatible storage, and it does seem very attractive for hobbyists at least. Full integration with their WAF too.
