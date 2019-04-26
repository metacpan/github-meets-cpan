FROM metacpan/metacpan-base:latest
ADD . /code
WORKDIR /code
RUN cpm install -g --cpanfile cpanfile
EXPOSE 3000
CMD ["morbo", "script/app.pl"]
