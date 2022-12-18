FROM nginx:alpine

RUN apk add --update-cache --repository http://dl-cdn.alpinelinux.org/alpine/edge/community/ zola git curl

ADD "https://api.github.com/repos/bspwr/blog/commits?per_page=1" latest_commit
RUN git clone https://github.com/BSpwr/blog.git /blog --recurse-submodules

RUN rm -r /usr/share/nginx/html
RUN cd /blog && zola build --output-dir /usr/share/nginx/html