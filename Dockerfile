ARG ubuntu_version

FROM ubuntu:$ubuntu_version

LABEL "com.github.actions.name"="Odoo custom addons test action"
LABEL "com.github.actions.description"="Test yout Odoo's custom addons"

LABEL version="0.1.0"
LABEL repository="https://github.com/fr33co/odoo-ci-test"
LABEL maintainer="Angel Guadarrama"

ENV LANG C.UTF-8
USER root

# Set timezone
ENV TZ=$timezone
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/time

# Install some deps, lessc and less-plugin-clean-css, and wkhtmltopdf
RUN set -x; \
        apt-get update \
        && apt-get install -y --no-install-recommends \
            ca-certificates \
            curl \
            gettext \
            git \
            gnupg \
            lsb-release \
            software-properties-common

# Install wkhtml
RUN case $(lsb_release -c -s) in \
      focal) WKHTML_DEB_URL=https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.focal_amd64.deb ;; \
      jammy) WKHTML_DEB_URL=https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb ;; \
    esac \
    && curl -sSL $WKHTML_DEB_URL -o /tmp/wkhtml.deb \
    && apt update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -qq -y --no-install-recommends /tmp/wkhtml.deb  \
    && rm /tmp/wkhtml.deb

# Install nodejs dependencies
RUN case $(lsb_release -c -s) in \
      focal) NODE_SOURCE="deb https://deb.nodesource.com/node_15.x focal main" \
             && curl -sSL https://deb.nodesource.com/gpgkey/nodesource.gpg.key | apt-key add - ;; \
      jammy) NODE_SOURCE="deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" \
             && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg ;; \
    esac \
    && echo "$NODE_SOURCE" | tee /etc/apt/sources.list.d/nodesource.list \
    && apt update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -qq nodejs

# less is for odoo<12
RUN npm install -g rtlcss less@3.0.4 less-plugin-clean-css

# Install postgresql client
RUN curl -sSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -s -c`-pgdg main" > /etc/apt/sources.list.d/pgclient.list \
    && apt update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -qq postgresql-client-12

RUN add-apt-repository -y ppa:deadsnakes/ppa

ARG python_version

# Install build dependencies for python libs commonly used by Odoo
RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -qq --no-install-recommends \
       build-essential \
       python${python_version}-dev \
       python${python_version}-venv \
       python3 \
       python3-venv \
       libpq-dev \
       libxml2-dev \
       libxslt1-dev \
       libz-dev \
       libxmlsec1-dev \
       libldap2-dev \
       libsasl2-dev \
       libjpeg-dev \
       libcups2-dev \
       default-libmysqlclient-dev \
       swig \
       libffi-dev \
       pkg-config

# Install Odoo
ARG odoo_version
ENV ODOO_VERSION $odoo_version
ARG ODOO_RELEASE=latest
RUN set -x; \
        curl -o odoo.deb -sSL http://nightly.odoo.com/${ODOO_VERSION}/nightly/deb/odoo_${ODOO_VERSION}.${ODOO_RELEASE}_all.deb \
        && dpkg --force-depends -i odoo.deb \
        && apt-get update \
        && apt-get -y install -f --no-install-recommends \
        && rm -rf /var/lib/apt/lists/* odoo.deb

# Copy Odoo configuration file to the container
COPY ./config/odoo.conf /etc/odoo/
RUN chown odoo -Rf /etc/odoo/*

# Copy wait-for-psql.py to the container
COPY wait-for-psql.py /usr/local/bin/wait-for-psql.py

# Copy entrypoint script to the container
COPY entrypoint.sh /entrypoint.sh

# Copy scripts to the container
COPY bin/* /usr/local/bin/

# Mount /var/lib/odoo to allow restoring filestore and /mnt/extra-addons for users addons
RUN mkdir -p /mnt/extra-addons \
        && chown -R odoo /mnt/extra-addons
VOLUME ["/var/lib/odoo", "/mnt/extra-addons"]

ENV ODOO_RC /etc/odoo/odoo.conf
ENV OPENERP_SERVER=/etc/odoo/odoo.conf
ENV ODOO_VERSION=$odoo_version
ENV PGHOST=postgres
ENV PGUSER=odoo
ENV PGPASSWORD=odoo
ENV PGDATABASE=odoo

# Set default user when running the container
USER odoo

ENTRYPOINT ["/entrypoint.sh"]

CMD ["odoo"]