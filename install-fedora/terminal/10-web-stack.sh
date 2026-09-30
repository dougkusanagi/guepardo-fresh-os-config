#!/usr/bin/env bash

section "Web Stack"
dnf_update

dnf_install \
  php \
  php-cli \
  php-fpm \
  php-common \
  php-mbstring \
  php-xml \
  php-curl \
  php-gd \
  php-pecl-imagick \
  php-pecl-zip \
  php-bcmath \
  php-intl \
  php-mysqlnd \
  php-pgsql \
  php-pdo \
  php-pecl-redis5 \
  php-opcache \
  php-soap \
  php-process \
  mariadb-server

enable_system_service mariadb

log "Keeping the distribution's MariaDB root authentication unchanged."

install_composer

add_line_if_missing "export PATH=\"\$HOME/.config/composer/vendor/bin:\$PATH\"" "$TARGET_HOME/.bashrc"
add_line_if_missing "export PATH=\"\$HOME/.bun/bin:\$PATH\"" "$TARGET_HOME/.bashrc"
export PATH="$HOME/.config/composer/vendor/bin:$HOME/.bun/bin:$PATH"
success "Shell PATH updated for Composer and Bun"

dnf_install nss-tools xsel

add_line_if_missing 'alias copy="xsel -b"' "$TARGET_HOME/.bashrc"
add_line_if_missing 'alias paste="xsel -b -o"' "$TARGET_HOME/.bashrc"
success "Clipboard aliases configured: copy, paste"
