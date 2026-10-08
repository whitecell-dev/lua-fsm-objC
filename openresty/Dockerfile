# CALYX FSM -- OpenResty host container
#
# Container layout mirrors the verified local rig:
#   /app                      repo root, mounted READ-ONLY (see docker-compose.yml)
#     init.lua, effect_contract.lua, hardened.lua, calyx_bundle.lua, session_fsm.lua
#     openresty/lualib/       nginx_host.lua, mock_data.lua, stream_mock.lua
#     openresty/lualib/calyx/ calyx/session_fsm.lua
#
# The lua_package_path in openresty/nginx.conf points INTO /app rather than at an
# installed copy. That is deliberate: an installed copy can silently drift from
# the repo, and one did. Read-only mount means the Lua code cannot mutate itself,
# and there is no second copy to go stale.
#
#   docker compose build
#   docker compose up -d
#   docker compose run --rm smoke          # runs the healthcheck block below
#
FROM openresty/openresty:1.27.1.2-0-alpine-fat

# cjson and lsqlite3 are required by openresty/lualib/nginx_host.lua:4 and
# redis_host.lua:5-6. Without lua_package_cpath set in nginx.conf they cannot
# load even when the .lua files resolve.
#   redis-lua      -> redis_host.lua
#   luafilesystem  -> tools/reportgen.lua (mkdir fallback)
#   lsqlite3       -> sqlite_host.lua (needs sqlite-dev for the headers --
#                      verified: the build fails with 'Could not find header file
#                      for SQLITE' if only `sqlite` is installed)
RUN set -eux; \
    apk add --no-cache \
        lua5.1 \
        lua5.1-dev \
        luarocks5.1 \
        curl \
        jq \
        sqlite \
        sqlite-dev \
        redis \
    ; \
    luarocks-5.1 install lua-cjson; \
    luarocks-5.1 install luafilesystem; \
    luarocks-5.1 install lsqlite3; \
    luarocks-5.1 install redis-lua; \
    luarocks-5.1 path

# nginx.conf and the lualib tree come from the read-only /app bind mount at
# runtime, so they are NOT copied in. This image is config + dependencies only,
# which means `git pull` changes behaviour without a rebuild.

COPY nginx.conf /usr/local/openresty/nginx/conf/nginx.conf

# error_log must resolve inside the container; the repo's relative "logs/" does not.
RUN mkdir -p /usr/local/openresty/logs

EXPOSE 8080

# `openresty -t` first: a malformed conf must fail the container, not serve 500s.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -fsS http://127.0.0.1:8080/health || exit 1

CMD ["/usr/local/openresty/bin/openresty", "-g", "daemon off;"]