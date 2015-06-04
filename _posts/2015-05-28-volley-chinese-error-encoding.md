---
layout: post
title: "Volley中文乱码解决方案"
category: 日志
tags: 
- Volley
- UTF8

date: 2015-05-20 02:23:57+08:00
--- 
### Volley中文乱码解决方案

Override `Request`里面的`parseNetworkResponse`即可。

	@Override
	protected Response<String> parseNetworkResponse(NetworkResponse response) {
	    String str = null;
	    try {
	        str = new String(response.data, getParamsEncoding());
	    } catch (UnsupportedEncodingException e) {
	        // TODO Auto-generated catch block
	        e.printStackTrace();
	    }
	    return Response.success(str, HttpHeaderParser.parseCacheHeaders(response));
	}
            
            
