# SwiftCGI-Demo
A minimal application that demonstrates how to set up a basic [SwiftCGI](https://github.com/ianthetechie/SwiftCGI) project.

# Quick Start
1. Clone this repo.
2. Open the SwiftCGI Demo project.
3. Run the project.
4. [RECOMMENDED] Configure nginx to serve fcgi from your application (a full nginx tutorial may come later if I get
   bored, but for now, the following nginx.conf snippet should suffice... Put this inside your server block).
   Alternatively, you may use the embedded HTTP server scheme, which starts a (rather expreimental a this point)
   local HTTP server, which can be used to get started. I do NOT recommend this for serious use though. SwiftCGI is
   designed, first and foremost, for FCGI app development.

```
location /cgi {
    fastcgi_pass    localhost:9000;
    fastcgi_param   SCRIPT_FILENAME /scripts$fastcgi_script_name;
    include         fastcgi_params;
}
```


## License This project is distributed under the terms of the 2-clause
BSD license. TL;DR - if the use of this product causes the death of
your firstborn, I'm not responsible (it is provided as-is; no warranty,
liability, etc.) and if you redistribute this with or without
modification, you need to credit me and copy the license along with
the code. Otherwise, you can pretty much do what you want ;)
