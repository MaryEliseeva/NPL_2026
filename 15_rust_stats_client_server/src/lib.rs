//! Статистические функции, общие для сервера (и тестов).

pub fn sum(xs: &[f64]) -> f64 {
    xs.iter().sum()
}

pub fn mean(xs: &[f64]) -> f64 {
    sum(xs) / xs.len() as f64
}

pub fn sorted(xs: &[f64]) -> Vec<f64> {
    let mut v = xs.to_vec();
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    v
}

pub fn median(xs: &[f64]) -> f64 {
    percentile(xs, 50.0)
}

/// Перцентиль с линейной интерполяцией между соседними элементами.
pub fn percentile(xs: &[f64], p: f64) -> f64 {
    let v = sorted(xs);
    let pos = (p / 100.0) * (v.len() - 1) as f64;
    let lo = pos.floor() as usize;
    let hi = pos.ceil() as usize;
    v[lo] + (v[hi] - v[lo]) * (pos - lo as f64)
}

/// Мода: все значения, встречающиеся чаще всего.
pub fn mode(xs: &[f64]) -> (Vec<f64>, usize) {
    let v = sorted(xs);
    let mut best: Vec<f64> = Vec::new();
    let mut best_count = 0;
    let mut i = 0;
    while i < v.len() {
        let mut j = i;
        while j < v.len() && v[j] == v[i] {
            j += 1;
        }
        let c = j - i;
        if c > best_count {
            best_count = c;
            best = vec![v[i]];
        } else if c == best_count {
            best.push(v[i]);
        }
        i = j;
    }
    (best, best_count)
}

/// Выборочная дисперсия (делитель n - 1).
pub fn variance(xs: &[f64]) -> f64 {
    if xs.len() < 2 {
        return 0.0;
    }
    let m = mean(xs);
    xs.iter().map(|x| (x - m).powi(2)).sum::<f64>() / (xs.len() - 1) as f64
}

pub fn std_dev(xs: &[f64]) -> f64 {
    variance(xs).sqrt()
}

pub fn min(xs: &[f64]) -> f64 {
    xs.iter().cloned().fold(f64::INFINITY, f64::min)
}

pub fn max(xs: &[f64]) -> f64 {
    xs.iter().cloned().fold(f64::NEG_INFINITY, f64::max)
}

/// Выбросы по правилу межквартильного размаха: за пределами [Q1 - 1.5·IQR; Q3 + 1.5·IQR].
pub fn outliers(xs: &[f64]) -> Vec<f64> {
    let q1 = percentile(xs, 25.0);
    let q3 = percentile(xs, 75.0);
    let iqr = q3 - q1;
    xs.iter()
        .cloned()
        .filter(|&x| x < q1 - 1.5 * iqr || x > q3 + 1.5 * iqr)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn basics() {
        let xs = [2.0, 4.0, 4.0, 4.0, 5.0, 5.0, 7.0, 9.0];
        assert_eq!(mean(&xs), 5.0);
        assert_eq!(median(&xs), 4.5);
        assert_eq!(mode(&xs), (vec![4.0], 3));
        assert!((std_dev(&xs) - 2.138).abs() < 1e-3);
        assert_eq!(percentile(&[1.0, 2.0, 3.0, 4.0], 50.0), 2.5);
    }
}
