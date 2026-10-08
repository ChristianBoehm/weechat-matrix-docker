FROM alpine:3.22

RUN apk add --no-cache weechat weechat-python weechat-matrix socat \
 && adduser -D -h /home/weechat weechat \
 && printf '%s\n' \
      '#!/bin/sh' \
      'mkdir -p "$HOME/.local/share/weechat/python/autoload"' \
      'ln -sf /usr/share/weechat/python/weechat-matrix.py "$HOME/.local/share/weechat/python/autoload/"' \
      'ln -sf /usr/share/weechat/python/autosave.py "$HOME/.local/share/weechat/python/autoload/"' \
      'socat TCP-LISTEN:8444,bind=0.0.0.0,reuseaddr,fork TCP:127.0.0.1:8443 >/dev/null 2>&1 &' \
      'if [ -n "$MATRIX_AUTO_IGNORE_NEW_DEVICES" ]; then set -- -r "/set matrix.network.auto_ignore_new_devices $MATRIX_AUTO_IGNORE_NEW_DEVICES" "$@"; fi' \
      'exec weechat "$@"' \
      > /usr/local/bin/weechat-entrypoint \
 && chmod +x /usr/local/bin/weechat-entrypoint \
 && chown -R weechat:weechat /home/weechat

COPY <<'PYEOF' /usr/share/weechat/python/autosave.py
import os

import weechat

dirty = set()


def conf_for_option(option):
    head = option.split(".", 1)[0] if option else ""
    if head in ("weechat", "plugins", ""):
        return "weechat"
    d = weechat.info_get("weechat_config_dir", "")
    if d and os.path.exists(os.path.join(d, head + ".conf")):
        return head
    return "weechat"


def on_config_changed(data, option, value):
    dirty.add(conf_for_option(option))
    return weechat.WEECHAT_RC_OK


def autosave_timer(data, remaining_calls):
    if dirty:
        buf = weechat.buffer_search("weechat", "weechat")
        for conf in list(dirty):
            weechat.command(buf, "/save " + conf)
        dirty.clear()
    return weechat.WEECHAT_RC_OK


weechat.register("autosave", "", "1.0", "",
                 "flush config changes to disk periodically", "", "")
weechat.hook_config("*", "on_config_changed", "")
weechat.hook_timer(15000, 0, 0, "autosave_timer", "")
PYEOF

# Script code from the maintained fork (compose build context "fork", the
# signed tag of ChristianBoehm/weechat-matrix pinned in docker-compose.yml). It replaces the files of the Alpine
# package, which pins the 2023 upstream commit; the package is still installed
# for its dependencies (nio, olm, cryptography, ...).
COPY --from=fork main.py /usr/share/weechat/python/weechat-matrix.py
COPY --from=fork matrix/ /usr/lib/python3.12/site-packages/matrix/
COPY --from=fork --chmod=755 contrib/matrix_sso_helper.py /usr/bin/matrix_sso_helper
COPY --from=fork --chmod=755 contrib/matrix_upload.py /usr/bin/matrix_upload
COPY --from=fork --chmod=755 contrib/matrix_decrypt.py /usr/bin/matrix_decrypt
COPY --from=fork --chmod=755 contrib/matrix_cross_sign.py /usr/bin/matrix_cross_sign
RUN rm -rf /usr/lib/python3.12/site-packages/matrix/__pycache__ \
 && python3 -m compileall -q /usr/lib/python3.12/site-packages/matrix \
 && grep -q 'WEECHAT_SCRIPT_VERSION = "0.3.5"' /usr/share/weechat/python/weechat-matrix.py

USER weechat
WORKDIR /home/weechat
ENTRYPOINT ["/usr/local/bin/weechat-entrypoint"]
CMD []
