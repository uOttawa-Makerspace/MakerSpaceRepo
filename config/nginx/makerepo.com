upstream makerspacerepo {
	server unix:/var/run/makerspacerepo/unicorn.sock fail_timeout=0;
}
server {
	client_max_body_size 5000M;
	listen       80 default_server;
	server_name  makerepo.com www.makerepo.com;
	root         /home/deploy/apps/Makerepo/current/public/;

	try_files $uri @makerspacerepo;

	location @makerspacerepo {
		proxy_redirect    off;
		proxy_set_header  X-Forwarded-For $proxy_add_x_forwarded_for;
		proxy_set_header  Host              $http_host;
		proxy_pass http://makerspacerepo;
	}

	error_page 404 /404.html;
	location = /40x.html {
	}

	error_page 500 502 503 504 /50x.html;
	location = /50x.html {
	}
}
