FROM debian:bookworm-slim

# Debian slim excludes documentation when unpacking packages, but Postfix's
# permission manifest includes its man pages (including mailq alternatives).
# Keep those packaged files so set-permissions can validate the full install.
RUN printf 'path-include=/usr/share/man/*\npath-include=/usr/share/doc/*\n' \
      > /etc/dpkg/dpkg.cfg.d/zz-postfix-documentation

# Prevent package installation from starting daemons while building the image.
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && \
    chmod +x /usr/sbin/policy-rc.d && \
    apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends postfix ca-certificates ruby ruby-net-smtp && \
    rm -rf /var/lib/apt/lists/* && \
    rm /usr/sbin/policy-rc.d

# Fail the build, rather than restart-loop at deployment, if a packaged file
# required by the permission manifest is absent. Runtime repeats this check for
# the persistent queue volume.
RUN postfix set-permissions && postfix check

# Run without chroots: DNS and CA files stay in the container filesystem, not
# in the persistent queue volume. Preserve Debian's service definitions.
RUN awk 'BEGIN { OFS="\t" } /^[^#[:space:]]/ && NF >= 8 { $5="n" } { print }' \
      /etc/postfix/master.cf > /etc/postfix/master.cf.new && \
    mv /etc/postfix/master.cf.new /etc/postfix/master.cf

COPY entrypoint.rb /usr/local/bin/mail-entrypoint
COPY healthcheck.rb /usr/local/bin/mail-healthcheck
ENTRYPOINT ["ruby", "/usr/local/bin/mail-entrypoint"]
