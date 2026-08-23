#include "OpusBridge.h"

int fmo_opus_configure_voice_encoder(OpusEncoder *encoder) {
    int status = opus_encoder_ctl(encoder, OPUS_SET_BITRATE(OPUS_AUTO));
    if (status != OPUS_OK) return status;
    status = opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY(4));
    if (status != OPUS_OK) return status;
    status = opus_encoder_ctl(encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
    if (status != OPUS_OK) return status;
    status = opus_encoder_ctl(encoder, OPUS_SET_VBR(1));
    if (status != OPUS_OK) return status;
    status = opus_encoder_ctl(encoder, OPUS_SET_VBR_CONSTRAINT(1));
    if (status != OPUS_OK) return status;
    return opus_encoder_ctl(encoder, OPUS_SET_MAX_BANDWIDTH(OPUS_BANDWIDTH_SUPERWIDEBAND));
}
