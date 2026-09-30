#!/usr/bin/env bash

section "Web Stack"
apt_update

apt_install \
  php \
  php-cli \
  php-fpm \
  php-common \
  php-mbstring \
  php-xml \
  php-curl \
  php-gd \
  php-imagick \
  php-zip \
  php-bcmath \
  php-intl \
  php-mysql \
  php-pgsql \
  php-sqlite3 \
  php-redis \
  php-dom \
  php-soap \
  mysql-server

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY-RUN] Would ensure PHP OPcache is available"
elif command -v php >/dev/null 2>&1 && php -m 2>/dev/null | grep -Fqi "Zend OPcache"; then
  success "PHP OPcache is already available"
else
  PHP_OPCACHE_PACKAGES=(php-opcache)
  while IFS= read -r package; do
    [[ "$package" == "php-opcache" ]] || PHP_OPCACHE_PACKAGES+=("$package")
  done < <(
    apt-cache search --names-only '^php[0-9][0-9.]*-opcache$' 2>/dev/null \
      | awk '{print $1}' \
      | sort -Vr
  )
  apt_install_first_available "${PHP_OPCACHE_PACKAGES[@]}"
fi

enable_system_service mysql

log "Keeping the distribution's MySQL root authentication unchanged."

install_composer

add_line_if_missing "export PATH=\"\$HOME/.config/composer/vendor/bin:\$PATH\"" "$TARGET_HOME/.bashrc"
add_line_if_missing "export PATH=\"\$HOME/.bun/bin:\$PATH\"" "$TARGET_HOME/.bashrc"
export PATH="$HOME/.config/composer/vendor/bin:$HOME/.bun/bin:$PATH"
success "Shell PATH updated for Composer and Bun"

apt_install libnss3-tools xsel

add_line_if_missing 'alias copy="xsel -b"' "$TARGET_HOME/.bashrc"
add_line_if_missing 'alias paste="xsel -b -o"' "$TARGET_HOME/.bashrc"
success "Clipboard aliases configured: copy, paste"
