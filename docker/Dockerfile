FROM wordpress:php5.6-fpm
MAINTAINER OMAR ABU AJAMIEH
RUN apt-get update && apt-get install net-tools python-dev python-pip nginx  vim -y && pip install virtualenv && pip install gunicorn
COPY wordpress /etc/nginx/sites-available/wordpress
RUN ln -s /etc/nginx/sites-available/wordpress /etc/nginx/sites-enabled/
RUN rm /etc/nginx/sites-enabled/default
COPY runme.sh /opt/runme.sh
