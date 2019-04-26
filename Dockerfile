FROM metacpan/metacpan-base:latest
ADD . /code
WORKDIR /code
RUN cpm install --without-test -g --cpanfile cpanfile
EXPOSE 3000
CMD ["morbo", "script/app.pl"]
