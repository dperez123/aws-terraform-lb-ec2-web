output "elb_dns_name" {
  ##output the dns of the load balancer web-lb
  value = aws_lb.web_lb.dns_name
}