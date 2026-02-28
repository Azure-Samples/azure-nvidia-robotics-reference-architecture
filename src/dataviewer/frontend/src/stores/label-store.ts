/**
 * Label store for managing episode labels and available label options.
 */

import { create } from 'zustand';
import { devtools } from 'zustand/middleware';

interface LabelState {
    /** Available label options for the current dataset */
    availableLabels: string[];
    /** Labels per episode: episode index -> label list */
    episodeLabels: Record<number, string[]>;
    /** Whether the label data has been loaded */
    isLoaded: boolean;
    /** Label filter: only show episodes with these labels (empty = show all) */
    filterLabels: string[];
}

interface LabelActions {
    /** Set available label options */
    setAvailableLabels: (labels: string[]) => void;
    /** Add a new label option */
    addLabelOption: (label: string) => void;
    /** Set all episode labels at once (bulk load) */
    setAllEpisodeLabels: (episodes: Record<string, string[]>) => void;
    /** Set labels for a specific episode */
    setEpisodeLabels: (episodeIndex: number, labels: string[]) => void;
    /** Toggle a label on/off for an episode */
    toggleLabel: (episodeIndex: number, label: string) => void;
    /** Set filter labels */
    setFilterLabels: (labels: string[]) => void;
    /** Toggle a filter label */
    toggleFilterLabel: (label: string) => void;
    /** Mark loaded */
    setLoaded: (loaded: boolean) => void;
    /** Reset store */
    reset: () => void;
}

type LabelStore = LabelState & LabelActions;

const DEFAULT_LABELS = ['SUCCESS', 'FAILURE', 'PARTIAL'];

const initialState: LabelState = {
    availableLabels: DEFAULT_LABELS,
    episodeLabels: {},
    isLoaded: false,
    filterLabels: [],
};

export const useLabelStore = create<LabelStore>()(
    devtools(
        (set, get) => ({
            ...initialState,

            setAvailableLabels: (labels) => {
                set({ availableLabels: labels }, false, 'setAvailableLabels');
            },

            addLabelOption: (label) => {
                const normalized = label.trim().toUpperCase();
                if (!normalized) return;
                const { availableLabels } = get();
                if (!availableLabels.includes(normalized)) {
                    set(
                        { availableLabels: [...availableLabels, normalized] },
                        false,
                        'addLabelOption',
                    );
                }
            },

            setAllEpisodeLabels: (episodes) => {
                const parsed: Record<number, string[]> = {};
                for (const [key, labels] of Object.entries(episodes)) {
                    parsed[Number(key)] = labels;
                }
                set({ episodeLabels: parsed }, false, 'setAllEpisodeLabels');
            },

            setEpisodeLabels: (episodeIndex, labels) => {
                const { episodeLabels } = get();
                set(
                    { episodeLabels: { ...episodeLabels, [episodeIndex]: labels } },
                    false,
                    'setEpisodeLabels',
                );
            },

            toggleLabel: (episodeIndex, label) => {
                const { episodeLabels } = get();
                const current = episodeLabels[episodeIndex] || [];
                const updated = current.includes(label)
                    ? current.filter((l) => l !== label)
                    : [...current, label];
                set(
                    { episodeLabels: { ...episodeLabels, [episodeIndex]: updated } },
                    false,
                    'toggleLabel',
                );
            },

            setFilterLabels: (labels) => {
                set({ filterLabels: labels }, false, 'setFilterLabels');
            },

            toggleFilterLabel: (label) => {
                const { filterLabels } = get();
                const updated = filterLabels.includes(label)
                    ? filterLabels.filter((l) => l !== label)
                    : [...filterLabels, label];
                set({ filterLabels: updated }, false, 'toggleFilterLabel');
            },

            setLoaded: (loaded) => {
                set({ isLoaded: loaded }, false, 'setLoaded');
            },

            reset: () => {
                set(initialState, false, 'reset');
            },
        }),
        { name: 'label-store' },
    ),
);
