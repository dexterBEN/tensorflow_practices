"""Shared camera, H.264/RTP and AI appsink pipeline for the PYNQ notebook.

Call after Gst.init(None). This function builds the pipeline without starting it;
the notebook owns callbacks, signaling, inference and shutdown.
"""

import re

import gi

gi.require_version("Gst", "1.0")
from gi.repository import Gst

PIPELINE_TEMPLATE = """
v4l2src name=camera_source device=/dev/video0
! image/jpeg,width={width},height={height},framerate={camera_fps}/1
! jpegdec
! tee name=shared
shared. ! queue max-size-buffers=2 leaky=downstream
! videorate
! video/x-raw,framerate={video_fps}/1
! videoconvert
! video/x-raw,format=I420
! queue max-size-buffers=2 leaky=downstream
! x264enc name=video_encoder tune=zerolatency speed-preset=ultrafast bitrate=800 key-int-max=30
! video/x-h264,profile=constrained-baseline
! h264parse
! rtph264pay name=payloader pt=96 config-interval=-1 aggregate-mode=zero-latency
shared. ! valve name=ai_valve drop=false
! queue name=ai_queue leaky=downstream max-size-buffers=1 max-size-bytes=0 max-size-time=0
! videoconvert
! video/x-raw,format=BGR
! appsink name=ai_sink max-buffers=1 drop=true sync=false async=false emit-signals=false enable-last-sample=false wait-on-eos=false
"""

PIPELINE_DESCRIPTION = PIPELINE_TEMPLATE.format(
    width=320, height=240, camera_fps=30, video_fps=15,
)


def create_media_pipeline(width=320, height=240, camera_fps=30, video_fps=15):
    """Return pipeline, webrtc, appsink, ai_queue, camera_source, rtp_src_pad."""
    for value in (width, height, camera_fps, video_fps):
        if type(value) is not int or value <= 0:
            raise ValueError("Dimensions et cadences : entiers strictement positifs requis")
    if video_fps > camera_fps:
        raise ValueError("La cadence video ne doit pas depasser celle de la camera")
    description = PIPELINE_TEMPLATE.format(
        width=width, height=height, camera_fps=camera_fps, video_fps=video_fps,
    )
    pipeline = Gst.parse_launch(description)

    payloader = pipeline.get_by_name("payloader")

    if payloader is None:
        raise RuntimeError("Unable to find RTP payloader")

    # Création séparée de webrtcbin
    webrtc = Gst.ElementFactory.make("webrtcbin", "webrtc")

    if webrtc is None:
        raise RuntimeError("Unable to create webrtcbin")

    pipeline.add(webrtc)

    # Request pad manuel
    webrtc_sink_pad = webrtc.request_pad_simple("sink_%u")

    if webrtc_sink_pad is None:
        raise RuntimeError("Unable to request WebRTC sink pad")

    transceiver = webrtc_sink_pad.get_property("transceiver")
    if transceiver is None or transceiver.find_property("do-nack") is None:
        raise RuntimeError("Le transceiver doit proposer do-nack pour cet essai")
    transceiver.set_property("do-nack", True)

    rtp_src_pad = payloader.get_static_pad("src")

    if rtp_src_pad is None:
        raise RuntimeError("Unable to get RTP source pad")

    link_result = rtp_src_pad.link(webrtc_sink_pad)

    if link_result != Gst.PadLinkReturn.OK:
        raise RuntimeError(
            f"Unable to link RTP to WebRTC: {link_result.value_nick}"
        )

    print("Camera pipeline created: OK")
    print("WebRTC element created: OK")
    print("WebRTC sink pad:", webrtc_sink_pad.get_name())
    print("RTP -> WebRTC:", link_result.value_nick)
    appsink = pipeline.get_by_name("ai_sink")
    ai_queue = pipeline.get_by_name("ai_queue")
    camera_source = pipeline.get_by_name("camera_source")
    assert appsink is not None and ai_queue is not None and camera_source is not None
    assert description.count("v4l2src") == 1
    print("Camera sources in this pipeline: 1 (GStreamer only)")
    print(f"Camera: {width}x{height} @ {camera_fps}; video: {video_fps} fps; NACK: True")

    return pipeline, webrtc, appsink, ai_queue, camera_source, rtp_src_pad


def elements_by_factory(pipeline, factory_name):
    """Find internal elements without depending on their generated names."""
    elements = []
    iterator = pipeline.iterate_recurse()
    while True:
        result, element = iterator.next()
        if result == Gst.IteratorResult.OK:
            factory = element.get_factory()
            if factory is not None and factory.get_name() == factory_name:
                elements.append(element)
        elif result == Gst.IteratorResult.RESYNC:
            iterator.resync()
            elements.clear()
        elif result == Gst.IteratorResult.DONE:
            return elements
        else:
            raise RuntimeError("Impossible de parcourir le pipeline")


def _video_rtx_map(sdp):
    mapping = {}
    for section in re.split(r"(?=^m=)", sdp.replace("\r\n", "\n"), flags=re.MULTILINE):
        if not section.startswith("m=video "):
            continue
        media = section.splitlines()[0].split()
        if media[1] == "0":
            continue
        payloads = {int(value) for value in media[3:]}
        codecs = {
            int(pt): codec.lower()
            for pt, codec in re.findall(r"^a=rtpmap:(\d+) ([^/\s]+)/", section, re.MULTILINE)
        }
        for rtx_pt, parameters in re.findall(r"^a=fmtp:(\d+) (.+)$", section, re.MULTILINE):
            rtx_pt = int(rtx_pt)
            apt = re.search(r"(?:^|;)\s*apt=(\d+)(?:\s*;|\s*$)", parameters)
            if apt is None or codecs.get(rtx_pt) != "rtx":
                continue
            original_pt = int(apt.group(1))
            if {original_pt, rtx_pt} <= payloads and codecs.get(original_pt) == "h264":
                mapping[original_pt] = rtx_pt
    return mapping


def negotiated_rtx_map(offer_sdp, answer_sdp):
    """Require an H.264/RTX association accepted by both endpoints."""
    offered, accepted = _video_rtx_map(offer_sdp), _video_rtx_map(answer_sdp)
    mapping = {pt: rtx for pt, rtx in accepted.items() if offered.get(pt) == rtx}
    if 96 not in mapping:
        raise RuntimeError("L'offre et la reponse doivent negocier RTX pour H.264 PT 96")
    return mapping


def rtx_status(pipeline):
    status = []
    for element in elements_by_factory(pipeline, "rtprtxsend"):
        mapping = element.get_property("payload-type-map")
        status.append({
            "name": element.get_name(),
            "payload_type_map": mapping.to_string() if mapping is not None else None,
            "num_rtx_requests": element.get_property("num-rtx-requests"),
            "num_rtx_packets": element.get_property("num-rtx-packets"),
        })
    return status


def configure_rtx(pipeline, mapping):
    """Temporary workaround for the missing map observed on GStreamer 1.20.1."""
    if not mapping:
        raise ValueError("Verifier l'association RTX negociee avant de l'appliquer")
    value = Gst.Structure.new_from_string(
        "application/x-rtp-pt-map, "
        + ", ".join(f"{pt}=(uint){rtx}" for pt, rtx in sorted(mapping.items()))
    )
    for element in elements_by_factory(pipeline, "rtprtxsend"):
        element.set_property("payload-type-map", value.copy())
    return rtx_status(pipeline)
