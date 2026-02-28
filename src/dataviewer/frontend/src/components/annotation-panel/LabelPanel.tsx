/**
 * LabelPanel - multi-select label tagging for episodes.
 *
 * Displays available labels as toggleable badges, allows adding custom labels,
 * and auto-saves on toggle.
 */

import { useState, useCallback } from 'react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Plus, Save, Check } from 'lucide-react';
import { useLabelStore } from '@/stores/label-store';
import {
    useCurrentEpisodeLabels,
    useAddLabelOption,
    useSaveAllLabels,
} from '@/hooks/use-labels';

interface LabelPanelProps {
    episodeIndex: number;
}

export function LabelPanel({ episodeIndex }: LabelPanelProps) {
    const [newLabel, setNewLabel] = useState('');
    const availableLabels = useLabelStore((state) => state.availableLabels);
    const { currentLabels, toggle } = useCurrentEpisodeLabels(episodeIndex);
    const addOption = useAddLabelOption();
    const saveAll = useSaveAllLabels();

    const handleAddLabel = useCallback(() => {
        const normalized = newLabel.trim().toUpperCase();
        if (!normalized) return;
        addOption.mutate(normalized);
        setNewLabel('');
    }, [newLabel, addOption]);

    const handleKeyDown = useCallback(
        (e: React.KeyboardEvent) => {
            if (e.key === 'Enter') {
                e.preventDefault();
                handleAddLabel();
            }
        },
        [handleAddLabel],
    );

    return (
        <div className="space-y-3">
            <div className="flex items-center justify-between">
                <h3 className="text-sm font-medium">Episode Labels</h3>
                <Button
                    size="sm"
                    variant="ghost"
                    onClick={() => saveAll.mutate()}
                    disabled={saveAll.isPending}
                    title="Save all labels to metadata"
                    className="h-7 px-2 gap-1 text-xs"
                >
                    {saveAll.isSuccess ? <Check className="h-3 w-3" /> : <Save className="h-3 w-3" />}
                    {saveAll.isPending ? 'Saving...' : 'Save All'}
                </Button>
            </div>

            {/* Label toggles */}
            <div className="flex flex-wrap gap-2">
                {availableLabels.map((label) => {
                    const isSelected = currentLabels.includes(label);
                    return (
                        <button
                            key={label}
                            onClick={() => toggle(label)}
                            className="focus:outline-none"
                        >
                            <Badge
                                variant={isSelected ? 'default' : 'outline'}
                                className={`cursor-pointer select-none transition-all ${isSelected
                                        ? 'bg-primary text-primary-foreground shadow-sm'
                                        : 'hover:bg-accent'
                                    }`}
                            >
                                {isSelected && <Check className="h-3 w-3 mr-1" />}
                                {label}
                            </Badge>
                        </button>
                    );
                })}
            </div>

            {/* Add custom label */}
            <div className="flex gap-2">
                <Input
                    value={newLabel}
                    onChange={(e) => setNewLabel(e.target.value)}
                    onKeyDown={handleKeyDown}
                    placeholder="Add custom label..."
                    className="h-8 text-sm"
                />
                <Button
                    size="sm"
                    variant="outline"
                    onClick={handleAddLabel}
                    disabled={!newLabel.trim() || addOption.isPending}
                    className="h-8 px-3 gap-1"
                >
                    <Plus className="h-3 w-3" />
                    Add
                </Button>
            </div>

            {/* Current labels summary */}
            {currentLabels.length > 0 && (
                <div className="text-xs text-muted-foreground">
                    Applied: {currentLabels.join(', ')}
                </div>
            )}
        </div>
    );
}
