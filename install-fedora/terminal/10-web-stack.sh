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

if command -v systemctl >/dev/null 2>&1; then
  log "Enabling MariaDB service..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would enable and start MariaDB service"
  else
    sudo systemctl enable mariadb || true
    sudo systemctl start mariadb || true
  fi
  success "MariaDB service enabled"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY-RUN] Would configure MariaDB root account"
else
  if run_quiet sudo mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY ''; FLUSH PRIVILEGES;"; then
    success "MariaDB root account configured with empty password"
  else
    warn "Could not update the MariaDB root user."
  fi
fi

if command -v composer >/dev/null 2>&1; then
  log "Composer is already available."
else
  log "Installing Composer..."
  if [[ "$DRY_RUN" == "true" ]]; then
    log "[DRY-RUN] Would install Composer"
  else
    run_quiet php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    run_quiet php composer-setup.php
    sudo mv composer.phar /usr/local/bin/composer
    rm -f composer-setup.php
    success "Composer installed"
  fi
fi

add_line_if_missing "export PATH=\"\$HOME/.config/composer/vendor/bin:\$PATH\"" "$TARGET_HOME/.bashrc"
add_line_if_missing "export PATH=\"\$HOME/.bun/bin:\$PATH\"" "$TARGET_HOME/.bashrc"
export PATH="$HOME/.config/composer/vendor/bin:$HOME/.bun/bin:$PATH"
success "Shell PATH updated for Composer and Bun"

dnf_install nss-tools

add_line_if_missing 'alias copy="xsel -b"' "$TARGET_HOME/.bashrc"
add_line_if_missing 'alias paste="xsel -b -o"' "$TARGET_HOME/.bashrc"
success "Clipboard aliases configured: copy, paste"
