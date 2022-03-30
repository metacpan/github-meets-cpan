FROM metacpan/metacpan-base:latest
ADD . /code
WORKDIR /code
RUN cpm install --without-test -g --show-build-log-on-failure --cpanfile cpanfile
EXPOSE 3000
CMD ["morbo", "script/app.pl"]
