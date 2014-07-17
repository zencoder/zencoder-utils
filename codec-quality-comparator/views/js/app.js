var gengraph = function(svg, data, keyframes, width, height, margin, domain, color, label) {

  var x = d3.scale.linear()
      .domain([0, data.length])
      .range([0, width]);

  var y = d3.scale.linear()
      .domain(domain)
      .range([height, 0]);

  var xAxis = d3.svg.axis()
    .scale(x)
    .innerTickSize(-height)
    .tickPadding(10)
    .tickFormat("")
    .tickValues(keyframes)
    .orient("bottom");

  var yAxis = d3.svg.axis()
    .scale(y)
    .ticks(3)
    .orient("right");

  var line = d3.svg.line()
    .interpolate("monotone")
    .x(function(d) { return x(d.x); })
    .y(function(d) { return y(d.y); });

  svg = svg.append("g")
    .attr("transform", "translate(" + margin.left + "," + margin.top + ")");


  svg.append("g")
      .attr("class", "x axis")
      .attr("transform", "translate(0," + height + ")")
      .on("mouseover", function() {
        console.log(d3.select(this));
      })
      .call(xAxis)
      .selectAll("text");

  svg.append("g")
      .attr("class", "y axis")
      .attr("transform", "translate(" + width + ",0)")
      .call(yAxis)
      .append("text")
        .attr("y", 10)
        .attr("x", -10)
        .attr("fill", color)
        .style("text-anchor", "end")
        .text(label);

  svg.append("path")
    .datum(data)
    .attr("class", "line")
    .attr("stroke", color)
    .attr("stroke-width", "1.5px")
    .attr("fill", "none")
    .attr("d", line)

  var hover = svg.append("g")
    .style("display", "none")

  hover.append("text")
    .attr("x", 0)
    .attr("dy", "2.35em")

  svg.append("rect")
    .attr("fill", "none")
    .attr("pointer-events", "all")
    .attr("width", width)
    .attr("height", height)
    .on("mouseover", function() {
      hover.style("display", null);
    })
    .on("mouseout", function() {
      hover.style("display", "none");
    })
    .on("mousemove", function() {
      var x0 = x.invert(d3.mouse(this)[0]);
      var bisector = d3.bisector(function(d) { return d.x }).left
      var i = bisector(data, x0, 1);
      d = data[i];
      
      console.log("translate(" + x(d.x) + "," + y(d.y) + ")");
      hover.attr("transform", "translate(" + x(d.x) + "," + y(d.y) + ")");
      hover.select("text").text(d.y);
    })
}

var drawChart = function(data, keyframes) {

  var psnrData = data[0].data;
  var ssimData = data[1].data;

  var margin = {top: 20, right: 50, bottom: 30, left: 40},
    width = 960 - margin.left - margin.right,
    height = 100

  var colors = d3.scale.category10();

  var psnrDomain = [d3.min(psnrData, function(x) { return x.y }),
                    d3.max(psnrData, function(x) { return x.y })]
  var ssimDomain = [d3.min(ssimData, function(x) { return x.y }),
                    d3.max(ssimData, function(x) { return x.y })
  ]

  var svg = d3.select("body").append("svg")
    .attr("width", width + margin.left + margin.right)
    .attr("height", 500 + margin.top + margin.bottom)

  gengraph(svg, psnrData, keyframes, width, height, margin, psnrDomain, colors(0), "PSNR (dB)");

  svg.append("g")
    .attr("transform", "translate(" + margin.left + "," + margin.top/2 + ")")
    .append("text")
    .text("Keyframes = " + keyframes)

  margin.top = 120;
  gengraph(svg, ssimData, keyframes, width, height, margin, ssimDomain, colors(1), "SSIM");

}
