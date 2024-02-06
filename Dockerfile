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
            software-properties-common \
            pipx

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

# Install build dependencies for python libs commonly used by Odoo and OCA
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

# We use manifestoo to check licenses, development status and list addons and dependencies
RUN pipx install --pip-args="--no-cache-dir" "manifestoo>=0.3.1"

# Install pyproject-dependencies helper scripts.
ARG build_deps="setuptools-odoo wheel whool"
RUN pipx install --pip-args="--no-cache-dir" pyproject-dependencies
RUN pipx inject --pip-args="--no-cache-dir" pyproject-dependencies $build_deps

# Make a virtualenv for Odoo so we isolate from system python dependencies and
# make sure addons we test declare all their python dependencies properly
ARG setuptools_constraint
RUN python${python_version} -m venv /opt/odoo-venv \
    && /opt/odoo-venv/bin/pip install -U "setuptools$setuptools_constraint" "wheel" "pip" \
    && /opt/odoo-venv/bin/pip list
ENV PATH=/opt/odoo-venv/bin:$PATH

# Install Odoo (use ADD for correct layer caching)
ARG odoo_org_repo=odoo/odoo
ARG odoo_version
ADD https://api.github.com/repos/$odoo_org_repo/git/refs/heads/$odoo_version /tmp/odoo-version.json
RUN mkdir /tmp/getodoo \
    && (curl -sSL https://github.com/$odoo_org_repo/tarball/$odoo_version | tar -C /tmp/getodoo -xz) \
    && mv /tmp/getodoo/* /opt/odoo \
    && rmdir /tmp/getodoo
RUN pip install --no-cache-dir -e /opt/odoo && pip list

# Make an empty odoo.cfg
RUN echo "[options]" > /etc/odoo.cfg
ENV ODOO_RC=/etc/odoo.cfg
ENV OPENERP_SERVER=/etc/odoo.cfg

COPY bin/* /usr/local/bin/

ENV PIP_DISABLE_PIP_VERSION_CHECK=1
ENV PIP_NO_PYTHON_VERSION_WARNING=1
ENV ODOO_VERSION=$odoo_version
ENV PGHOST=postgres
ENV PGUSER=odoo
ENV PGPASSWORD=odoo
ENV PGDATABASE=odoo
ENV ADDONS_DIR=.
ENV ADDONS_PATH=/opt/odoo/addons

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]