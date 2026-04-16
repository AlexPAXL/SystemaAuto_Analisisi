FROM nginx:1.25-alpine

# Eliminar la config por defecto de nginx
RUN rm /etc/nginx/conf.d/default.conf

# Copiar nuestra config dentro de la imagen (no mount)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Los archivos de la web se copian también
COPY . /usr/share/nginx/html/

EXPOSE 80
