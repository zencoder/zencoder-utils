# Codec Quality Comparator

## Hack Week 2014 Project

High Level Overview:
	Create an objective reference test for evaluating different implementations of codecs, technologies that claim to improve encoding efficiency, and updates/changes we make in our software.  This will also be used for validation and testing of updates we make to our encoding pipeline. [Timing depends on solution - we’ll look at Zartan, existing tools, etc. and determine a usable solution.  Initial guesstimate is 2-5 developer-weeks.]

Description / Info Statement:
    Currently it is difficult to quantify the following:
        Quality degradation of a transcode while varying options like bitrate, # of passes, etc.
        Quality comparisons of two codecs or two codec implementations when using comparable encoding configurations.
        Quality comparisons when upgrading various dependencies such as x264, ffmpeg.
    We don’t have an automated way to determine if a change causes a loss or improvement of quality. Ideally, changes would trigger quality regression tests and alert on quality changes.

Future Benefits: 
    Prevent inadvertent quality loss with code changes or dependency updates. 
    As a developer when adding new features, could quickly iterate over settings to get feedback.
    Could provide quality metrics to customers and a feature.

Task List:
    Evaluate existing tools vs roll-your-own:
        http://compression.ru/video/quality_measure/video_measurement_tool_en.html
        http://qpsnr.youlink.org/
        https://sites.google.com/site/sachinkagarwal/home/code-snippets/video-quality-analysis---part-2
    Define interface:
        Should minimally support comparison of re-encode vs original
        Optionally support single-file evaluation
        Should produce per-frame and average ssim, mos and possibly psnr.
        Output could be to stdout or to file, using CSV
        Define summary format to report on problem areas, specific issues identified.
    Choose test media. Should cover both high-quality HD sources down to low bitrate. Also cover screen casts, low and variable framerate sources and other types that are known to cause issues.
    Talk to Sean about Zartan - is there anything we can reuse? Or is this a tool that they would like to use from Zartan?
    Implement single path to validate assumptions. For example, command-line tool to that simply grabs a single frame given a frame # and outputs ssim values.
    Verify that changes in bitrate, # of passes, b-frames, etc cause the ssim data to change as expected.
    Add other statistic options, mos and ssim, if planned.
    Add support for reading each frame from both source and output at the same time and producing stat values.
    Add support for time ranges.
    Add support for reporting on specific types of issues like blocking.
    Integrate graphing tool to optionally produce quality loss over time, possibly allowing specific time range so frame-by-frame detail can be observed.
    Verify tool with the following:
        Compare with quality and bitrate settings, 1 and 2 pass
        Compare with various keyframe interval settings
        Compare with various profiles, bframes, etc.
        Compare with varying source types and source qualities (blocky to pristine)
    Create basic regression suite for at least one codec such as x264.