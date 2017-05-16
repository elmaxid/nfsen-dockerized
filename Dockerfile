####
# Netflow collector and local processing container
# using NFSen and NFDump for processing. This can
# be run standalone or in conjunction with a analytics
# engine that will perform time based graphing and
# stats summarization.
###

FROM debian:jessie
MAINTAINER Brent Salisbury <brent.salisbury@gmail.com>
MAINTAINER Rich Brown <richb.hanover+nfsen@gmail.com>

RUN apt-get update && apt-get install -y \
    apache2 \
    flex \
    gcc \
    libapache2-mod-php5 \
    libio-socket-inet6-perl \
    libio-socket-ssl-perl \
    libipc-run-perl \
    libmailtools-perl \
    librrd-dev \
    librrds-perl \
    libsys-syslog-perl \
    libwww-perl \
    nano \
    net-tools \
    perl-base \
    php5 \
    php5-common \
    rrdtool \
    tcpdump \
    supervisor \
    wget

# Cleanup apt-get cache
RUN apt-get clean

# Apache
EXPOSE 80
# NetFlow
EXPOSE 2055
# IPFIX
EXPOSE 4739
# sFlow
EXPOSE 6343
# nfsen src ip src node mappings per example
EXPOSE 9996

# mk some dirs
RUN mkdir -p /var/lock/apache2 /var/run/apache2 /var/log/supervisor

ENV NFSEN_VERSION 1.3.8
ENV NFDUMP_VERSION 1.6.13

# Install NFDump (this URL gives a fixed download location)
RUN    cd /usr/local/src \
    && wget  http://iweb.dl.sourceforge.net/project/nfdump/stable/nfdump-${NFDUMP_VERSION}/nfdump-${NFDUMP_VERSION}.tar.gz \
    && tar xfz nfdump-${NFDUMP_VERSION}.tar.gz && cd nfdump-${NFDUMP_VERSION}/ \
    && ./configure \
	  --enable-nfprofile \
	  --with-rrdpath=/usr/bin \
	  --enable-nftrack \
	  --enable-sflow \
    && make \
    && make install

# Configure php with the systems timezone, modifications are tagged with the word 'NFSEN_OPT' for future ref
# Recommended leaving the timezone as UTC as NFSen and NFCapd timestamps need to be in synch.
# Timing is also important for the agregates time series viewer for glabal visibility and analytics.
RUN    sed -i 's/^;date.timezone =/date.timezone \= \"UTC\"/g' /etc/php5/apache2/php.ini \
    && sed -i '/date.timezone = "UTC\"/i ; NFSEN_OPT Adjust your timezone for nfsen' /etc/php5/apache2/php.ini \
    && sed -i 's/^;date.timezone =/date.timezone \= \"UTC\"/g' /etc/php5/cli/php.ini \
    && sed -i '/date.timezone = "UTC\"/i ; NFSEN_OPT Adjust your timezone for nfsen' /etc/php5/cli/php.ini

# Retrieve nfsen
RUN mkdir -p /data/nfsen
WORKDIR /data
RUN wget http://iweb.dl.sourceforge.net/project/nfsen/stable/nfsen-${NFSEN_VERSION}/nfsen-${NFSEN_VERSION}.tar.gz \
    && tar xfz nfsen-${NFSEN_VERSION}.tar.gz \
# Configure NFSen config files
    && sed -i 's/"www";/"www-data";/g' nfsen-${NFSEN_VERSION}/etc/nfsen-dist.conf \
# Example how to fill in any flow source you want using | as a delimiter. Sort of long and gross though.
# Modify the pre-defined NetFlow v5/v9 line matching the regex 'upstream1'
    && sed -i  "s|'upstream1'    => { 'port' => '9995', 'col' => '#0000ff', 'type' => 'netflow' },| \
        'netflow-global'  => { 'port' => '2055', 'col' => '#0000ff', 'type' => 'netflow' },|g" \
         nfsen-${NFSEN_VERSION}/etc/nfsen-dist.conf \
# Bind port 6343 and an entry for sFlow collection
    && sed  -i "/%sources/a \
    'sflow-global'  => { 'port' => '6343', 'col' => '#0000ff', 'type' => 'sflow' }," nfsen-${NFSEN_VERSION}/etc/nfsen-dist.conf \
# Bind port 4739 and an entry for IPFIX collection. E.g. NetFlow v10
    && sed  -i "/%sources/a \
    'ipfix-global'  => { 'port' => '4739', 'col' => '#0000ff', 'type' => 'netflow' }," nfsen-${NFSEN_VERSION}/etc/nfsen-dist.conf \
    && cat nfsen-${NFSEN_VERSION}/etc/nfsen-dist.conf

# Add an account for NFSen as a member of the apache group
RUN useradd -d /var/netflow -G www-data -m -s /bin/false netflow

# Run the nfsen installer
WORKDIR /data/nfsen-${NFSEN_VERSION}
RUN perl ./install.pl etc/nfsen-dist.conf || true
RUN sleep 3

# Replace the main index.html file to redirect to /nfsen/nfsen.php
COPY replacement-index.html /var/www/html/index.html

# Patch up the VirtualHost so that /nfsen URLs are served from /var/www/nfsen
RUN sed -i.bak -e'/<\/VirtualHost>/ i \
       Alias "/nfsen" "/var/www/nfsen" \n\
' /etc/apache2/sites-available/000-default.conf 


WORKDIR /
# Add startup script for nfsen profile init
ADD ./start.sh /data/start.sh
# flow-generator binary for testing
ADD ./flow-generator /data/flow-generator
ADD	./supervisord.conf /etc/supervisord.conf

CMD bash -C '/data/start.sh'; '/usr/bin/supervisord'
