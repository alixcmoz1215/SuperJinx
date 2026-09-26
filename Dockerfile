# JinX | Super JinX : 3x-ui v2.9.4 one-click Railway edition
FROM ghcr.io/mhsanaei/3x-ui:v2.9.4

RUN apk add --no-cache nginx sqlite curl jq tzdata ca-certificates openssl procps \
 && mkdir -p /run/nginx /jinx/www/sub /etc/x-ui

COPY jinx/ /jinx/
RUN chmod +x /jinx/start.sh

ENV PORT=8080 \
    XUI_ENABLE_FAIL2BAN=false \
    TZ=Asia/Tehran

EXPOSE 8080
WORKDIR /app
ENTRYPOINT ["/jinx/start.sh"]
CMD []
