"""Per-beast settings for beast_anim.make_clips and the jaw split, plus the export targets."""

BEASTS = {
    'Sabertooth': dict(
        out='emerald_sabertooth',
        jaw=(0.87, -0.96, None, None),
        P=dict(H=1.238, walk_stride=0.34, walk_lift=0.09, walk_bob=0.008, toe_flex=35, walk_frames=36,
               run_stride=0.8, run_lift=0.17, run_bob=0.02, run_flex=10, run_frames=18, jaw_open=32, lunge=0.2,
               death_drop=0.22, death_side_lift=0.1, death_roll=82,
               special='leap', leap_dist=0.6, leap_height=0.24, bite_side=1.0),
    ),
    'Blisterback': dict(
        out='blisterback_ravager',
        jaw=(0.72, -1.11, 0.70, -1.38),
        P=dict(H=1.205, walk_stride=0.36, walk_lift=0.1, walk_bob=0.01, toe_flex=30, walk_frames=38,
               run_stride=0.75, run_lift=0.16, run_bob=0.02, run_flex=8, run_frames=20, jaw_open=30, lunge=0.2,
               death_drop=0.2, death_side_lift=0.1, death_roll=80, run_tail_pitch=8,
               special='leap', leap_dist=0.5, leap_height=0.2, bite_side=-1.0),
    ),
    'Spineback': dict(
        out='spineback_terror',
        jaw=(0.46, -1.23, 0.45, -1.48),
        P=dict(H=0.972, walk_stride=0.3, walk_lift=0.08, walk_bob=0.008, toe_flex=30, walk_frames=40,
               run_stride=0.6, run_lift=0.13, run_bob=0.018, run_flex=7, run_frames=20, jaw_open=28, lunge=0.2,
               death_drop=0.2, death_side_lift=0.1, death_roll=80, run_tail_pitch=4,
               special='spin', spin_side=1.0, special_frames=60, bite_side=1.0,
               tail_freq_base=2.6, tail_freq_tip=1.5, tail_damping=0.4),
    ),
}
