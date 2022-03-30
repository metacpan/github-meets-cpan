FROM metacpan/metacpan-base:latest

COPY . /code
WORKDIR /code

RUN cpanm --notest Carton && \
  cpanm --notest --local-lib local https://cpan.metacpan.org/authors/id/M/MO/MONGODB/MongoDB-v0.708.4.0.tar.gz && \
  carton install --deployment

EXPOSE 3000
 CMD ["carton", "exec", "morbo", "script/app.pl"]
