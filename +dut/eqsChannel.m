function H = eqsChannel(f, p)
%EQSCHANNEL Complex transfer function of a capacitive EQS-HBC body channel.
%
%   H = dut.eqsChannel(f, p) returns the complex voltage transfer function
%   from transmitter electrode to receiver input, evaluated at frequencies f
%   (Hz), for the parameter struct p from dut.channelParams.
%
%   Topology (capacitive / electro-quasistatic HBC):
%
%       TX o---- R_body ----+---- Z_return ----+
%                           |                  |
%                        Z_load            (earth return)
%                           |                  |
%                          GND ----------------+
%
%   where Z_return = 1/(j.w.C_return) is the device ground-plane return path
%   and Z_load = R_in || 1/(j.w.C_in) is the receiver termination.
%
%   The response is high-pass: below the corner set by C_return and the
%   termination the return-path impedance dominates and loss rises at
%   20 dB/decade; above it the response plateaus. This is the characteristic
%   EQS-HBC channel shape. The return-path impedance exceeds 1 Mohm below
%   1 MHz, which is why sub-MHz operation is lossy.
%
%   TERMINATION IS THE HEADLINE RESULT: moving from a 50-ohm termination to a
%   high-Z capacitive termination lifts the channel by ~40-50 dB. This
%   function reproduces that from the topology -- it is not fitted.
%
%   See also dut.channelParams.

    if nargin < 2, p = dut.channelParams(); end

    f = f(:).';
    w = 2*pi*f;

    % Guard DC: a purely capacitive return path has infinite impedance at
    % f = 0, so H(0) = 0 exactly. Computing it via 1/(j*w*C) would divide by
    % zero, so handle it explicitly rather than letting Inf propagate.
    H  = zeros(size(f));
    nz = f ~= 0;
    wn = w(nz);

    Z_return = 1 ./ (1j * wn * p.C_return);
    Y_load   = 1/p.R_in + 1j * wn * p.C_in;
    Z_load   = 1 ./ Y_load;

    H(nz) = p.k * Z_load ./ (Z_load + Z_return + p.R_body);
end
